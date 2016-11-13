#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"
#include "flags.h"
#include "myred.h"

#ifndef max
    #define max(a,b) ((a) > (b) ? (a) : (b))
#endif

static class MyREDClass : public TclClass
{
	public:
		MyREDClass():TclClass("Queue/DCTCP") {}
		TclObject* create(int argc, const char*const* argv)
		{
			return (new MyRED);
		}
} class_myred;

/* Initialize static members as 0 */
int MyRED::shared_buf_lim_[SHARED_BUFFER_NUM] = {0};
int MyRED::shared_buf_len_[SHARED_BUFFER_NUM] = {0};
int MyRED::shared_buf_mem_[SHARED_BUFFER_NUM] = {0};

MyRED::MyRED()
{
	q_ = new PacketQueue();

	debug_ = 0;

	thresh_ = 60;
	mean_pktsize_ = 9000;

	enable_buffer_ecn_ = 0;
	headroom_ = 0.375;
        min_buffer_ = 18000;

        enable_sp_ecn_ = 0;
        sp_thresh_ = 0;

	enable_shared_buf_ = 0;
	shared_buf_id_ = -1;
	alpha_ = 1;

	pkt_tot_ = 0;
	pkt_drop_ = 0;
	pkt_drop_ecn_ = 0;

        shared_qlen_tchan_ = NULL;
        port_qlen_tchan_ = NULL;

	bind_bool("debug_", &debug_);

	bind("thresh_", &thresh_);
	bind("mean_pktsize_", &mean_pktsize_);

	bind_bool("enable_buffer_ecn_", &enable_buffer_ecn_);
	bind("headroom_", &headroom_);
        bind("min_buffer_", &min_buffer_);

        bind_bool("enable_sp_ecn_", &enable_sp_ecn_);
        bind("sp_thresh_", &sp_thresh_);

	bind_bool("enable_shared_buf_", &enable_shared_buf_);
	bind("shared_buf_id_", &shared_buf_id_);
	bind("alpha_", &alpha_);

	bind("pkt_tot_", &pkt_tot_);
	bind("pkt_drop_", &pkt_drop_);
	bind("pkt_drop_ecn_", &pkt_drop_ecn_);
}

MyRED::~MyRED()
{
	delete q_;
}

/* return true if the buffer is overfilled and packet should get dropped */
bool MyRED::buffer_overfill(Packet* p)
{
	Tcl& tcl = Tcl::instance();
	int len = hdr_cmn::access(p)->size() + q_->byteLength();

	/* dynamic shared buffer allocation. If buf id is invalid, we use static buffer allocation instead. */
	if (enable_shared_buf_ && shared_buf_id_ >= 0 && shared_buf_id_ < SHARED_BUFFER_NUM) {
		int free_buffer = shared_buf_lim_[shared_buf_id_] - shared_buf_len_[shared_buf_id_];
		int thresh = alpha_ * free_buffer;
		if (debug_) {
			tcl.evalf("puts \"dynamic threshold: %f * %d = %d\"", alpha_, free_buffer, thresh);
		}

		if (len > thresh) {
			return true;
		} else {
			shared_buf_len_[shared_buf_id_] += hdr_cmn::access(p)->size();
			return false;
		}
        /* static per-port buffer allocation */
	} else {
		if (len > qlim_ * mean_pktsize_)
			return true;
		else
			return false;
	}
}

void MyRED::port_mark(Packet* p)
{
        hdr_flags* hf = hdr_flags::access(p);
        int len = hdr_cmn::access(p)->size() + q_->byteLength();

        if (hf->ect() && len > thresh_ * mean_pktsize_)
                hf->ce() = 1;
}

void MyRED::sp_mark(Packet* p)
{
        hdr_flags* hf = hdr_flags::access(p);

        if (!enable_shared_buf_ || shared_buf_id_ < 0 || shared_buf_id_ >= SHARED_BUFFER_NUM)
                return;

        if (hf->ect() && shared_buf_len_[shared_buf_id_] > sp_thresh_)
                hf->ce() = 1;
}

void MyRED::buffer_mark(Packet* p)
{
        hdr_flags* hf = hdr_flags::access(p);
        int len = hdr_cmn::access(p)->size() + q_->byteLength();
        double dynamic_thresh = -1;

        if (enable_shared_buf_ && shared_buf_id_ >= 0 && shared_buf_id_ < SHARED_BUFFER_NUM) {
                double buffer_thresh = alpha_ * (shared_buf_lim_[shared_buf_id_] - shared_buf_len_[shared_buf_id_]);
                dynamic_thresh = headroom_ * buffer_thresh;
                //printf("headroom_ %f dynamic_thresh %d\n", headroom_, int(dynamic_thresh));
                dynamic_thresh = max(dynamic_thresh, min_buffer_);
                //printf("new dynamic_thresh %d\n", int(dynamic_thresh));
        }

        if (hf->ect() && dynamic_thresh >= 0 && len > dynamic_thresh)
                hf->ce() = 1;
}


void MyRED::enque(Packet* p)
{
	pkt_tot_++;
        
        /* if the packet gets dropped */
        if (buffer_overfill(p)) {
		pkt_drop_++;
		/* the packet gets dropped before RED/ECN reacts */
		if (hdr_cmn::access(p)->size() + q_->byteLength() < thresh_ * mean_pktsize_)
			pkt_drop_ecn_++;
                drop(p);
        } else {
                q_->enque(p);
        }
}

Packet* MyRED::deque()
{
	Packet *p = q_->deque();

	if (p && enable_shared_buf_ && shared_buf_id_ >= 0 && shared_buf_id_ < SHARED_BUFFER_NUM) {
		shared_buf_len_[shared_buf_id_] -= hdr_cmn::access(p)->size();
	}

        if (!p)
                goto out;

        /* per-port ECN/RED marking */
        port_mark(p);
        /* per-service-pool ECN/RED marking */
        if (enable_sp_ecn_)
                sp_mark(p);
        /* buffer-aware ECN marking */
        if (enable_buffer_ecn_)
                buffer_mark(p);

out:
        trace_port_qlen();
        trace_shared_qlen();
        return p;
}

void MyRED::trace_port_qlen()
{
        if (!port_qlen_tchan_)
                return;

        char wrk[100] = {0};
        sprintf(wrk, "%g, %d\n", Scheduler::instance().clock(), q_->byteLength());
        Tcl_Write(port_qlen_tchan_, wrk, strlen(wrk));
}

void MyRED::trace_shared_qlen()
{
        if (!shared_qlen_tchan_ || shared_buf_id_ < 0 || shared_buf_id_ >= SHARED_BUFFER_NUM)
                return;

        char wrk[100] = {0};
        sprintf(wrk, "%g, %d\n", Scheduler::instance().clock(), shared_buf_len_[shared_buf_id_]);
        Tcl_Write(shared_qlen_tchan_, wrk, strlen(wrk));
}

/*
 * Usages:
 * - $q print: print size, # of members information of shared buffers
 * - $q register: register the port to its shared buffer
 * - $q trace-shared-qlen [file]: trace the shared buffer occupancy
 * - $q trace-port-qlen [file]: trace the per-port buffer occupancy
 * - $q set-shared-buffer [buffer_id] [buffer_size]: set size of a shared buffer
 */
int MyRED::command(int argc, const char*const* argv)
{
	Tcl& tcl = Tcl::instance();

	if (argc == 2) {
		if (strcmp(argv[1], "print") == 0) {
			for (int i = 0; i < SHARED_BUFFER_NUM; i++) {
				if (shared_buf_lim_[i] > 0) {
					tcl.evalf("puts \"Shared buffer %d: limit %d occupancy %d members %d\"",
						  i, shared_buf_lim_[i], shared_buf_len_[i], shared_buf_mem_[i]);
				}
			}

			return (TCL_OK);
		} else if (strcmp(argv[1], "register") == 0) {
			if (shared_buf_id_ >= 0 && shared_buf_id_ < SHARED_BUFFER_NUM)
				shared_buf_mem_[shared_buf_id_]++;

			return (TCL_OK);
		}
	} else if (argc == 3) {
                if (strcmp(argv[1], "trace-shared-qlen") == 0) {
                        int mode;
			const char *id = argv[2];
			Tcl& tcl = Tcl::instance();
			if (!(shared_qlen_tchan_ = Tcl_GetChannel(tcl.interp(), (char*)id, &mode))) {
                                tcl.evalf("puts \"Cannot attach %s for writing\"", id);
                                return (TCL_ERROR);
                        }

                        return (TCL_OK);
                } else if (strcmp(argv[1], "trace-port-qlen") == 0) {
                        int mode;
			const char *id = argv[2];
			Tcl& tcl = Tcl::instance();
			if (!(port_qlen_tchan_ = Tcl_GetChannel(tcl.interp(), (char*)id, &mode))) {
                                tcl.evalf("puts \"Cannot attach %s for writing\"", id);
                                return (TCL_ERROR);
                        }

                        return (TCL_OK);
                }
        } else if (argc == 4) {
		if (strcmp(argv[1], "set-shared-buffer") == 0) {
			int id =  atoi(argv[2]);
			int size = atoi(argv[3]);

			if (id >= 0 && id < SHARED_BUFFER_NUM && size > 0) {
				shared_buf_lim_[id] = size;
				if (debug_) {
					tcl.evalf("puts \"Set shared buffer %d size to %d\"", id, size);
				}
			} else {
				if (id < 0 || id >= SHARED_BUFFER_NUM) {
					tcl.evalf("puts \"Invalid shared buffer ID %d\"", id);
				} if (size <= 0) {
					tcl.evalf("puts \"Invalid shared buffer size %d\"", size);
				}
			}

			return (TCL_OK);
		}
	}

	return (Queue::command(argc, argv));
}
