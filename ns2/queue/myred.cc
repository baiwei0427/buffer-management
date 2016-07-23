#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "config.h"
#include "flags.h"
#include "myred.h"

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
//int MyRED::shared_buf_mem_[SHARED_BUFFER_NUM] = {0};

MyRED::MyRED()
{
	q_ = new PacketQueue();
	thresh_ = 60;
	mean_pktsize_ = 9000;
	debug_ = 0;
	enable_shared_buf_ = 0;
	shared_buf_id_ = -1;
	alpha_ = 1;

	bind("thresh_", &thresh_);
	bind("mean_pktsize_", &mean_pktsize_);
	bind_bool("debug_", &debug_);
	bind_bool("enable_shared_buf_", &enable_shared_buf_);
	bind("shared_buf_id_", &shared_buf_id_);
	bind("alpha_", &alpha_);
}

MyRED::~MyRED()
{
	delete q_;
}

/* return true if the buffer is overfilled and packet should get dropped */
bool MyRED::buffer_overfill(Packet* p)
{
	int len = hdr_cmn::access(p)->size() + q_->byteLength();

	/* static per-port buffer allocation */
	if (enable_shared_buf_ == 0)
	{
		if (len > qlim_ * mean_pktsize_)
			return true;
		else
			return false;
	}
	/* dynamic shared buffer allocation */
	else if (shared_buf_id_ >= 0 && shared_buf_id_ < SHARED_BUFFER_NUM)
	{
		int free_buffer = shared_buf_lim_[shared_buf_id_] - shared_buf_len_[shared_buf_id_];
		int thresh = alpha_ * free_buffer;
		if (debug_)
		{
			printf("dynamic threshold: %f * %d = %d", alpha_, free_buffer, thresh);
		}

		if (len > thresh)
			return true;
		else
			return false;
	}
	/* invalid shared buffer ID */
	else
	{
		return false;
	}
}

void MyRED::ecn_mark(Packet* p)
{
	hdr_flags* hf = hdr_flags::access(p);
	int len = hdr_cmn::access(p)->size() + q_->byteLength();

	if (len > thresh_ * mean_pktsize_ && hf->ect())
		hf->ce() = 1;
}

void MyRED::enque(Packet* p)
{
        if (buffer_overfill(p))
        {
                drop(p);
                return;
        }

	ecn_mark(p);
        q_->enque(p);
}

/*
 * Usages:
 * - $q print: print size, # of members information of shared buffers
 * - $q set-shared-buffer buffer_id buffer_size: set size of a shared buffer
 */
int MyRED::command(int argc, const char*const* argv)
{
	if (argc == 2)
	{
		if (strcmp(argv[1], "print") == 0)
		{
			for (int i = 0; i < SHARED_BUFFER_NUM; i++)
			{
				if (shared_buf_lim_[i] > 0)
				{
					printf("shared buffer %d: limit %d occupancy %d\n",
						i, shared_buf_lim_[i], shared_buf_len_[i]);
				}
			}
		}
	}
	if (argc == 4)
	{
		if (strcmp(argv[1], "set-shared-buffer") == 0)
		{
			int id =  atoi(argv[2]);
			int size = atoi(argv[3]);

			if (id >= 0 && id < SHARED_BUFFER_NUM && size > 0)
			{
				shared_buf_lim_[id] = size;
				if (debug_)
				{
					printf("Set shared buffer %d size to %d\n", id, size);
				}
			}
			else
			{
				if (id < 0 || id >= SHARED_BUFFER_NUM)
				{
					printf("Invalid shared buffer ID %d\n", id);
				}
				if (size <= 0)
				{
					printf("Invalid shared buffer size %d\n", size);
				}
			}
		}
	}

	return (Queue::command(argc, argv));
}

Packet* MyRED::deque()
{
        return (q_->deque());
}
