#ifndef ns_my_red_h
#define ns_my_red_h

#include "queue.h"

/* MyRED: a simple version of Random Early Detection (RED) for DCTCP-style ECN marking */

#define SHARED_BUFFER_NUM 1024  /* total number of shared buffers */

class MyRED : public Queue
{
public:
        MyRED();
        ~MyRED();
        virtual int command(int argc, const char*const* argv);

protected:
        void enque(Packet*);
	Packet* deque();
        bool buffer_overfill(Packet*);  /* whether the switch buffer is overfilled */
        void red_mark(Packet*); /* RED/ECN marking */
        void buffer_mark(Packet*);      /* buffer-aware ECN marking */
        void trace_shared_qlen();       /* trace the occupancy of the shared buffer */
        void trace_port_qlen(); /* trace per-port buffer occupancy */

        int debug_;     /* print necessary debug information or not */

        int thresh_;    /* ECN marking threshold in packet */
        int mean_pktsize_;      /* packet size in bytes */

        int enable_buffer_ecn_;        /* enable buffer-aware ECN */
        double headroom_;      /* headroom parameter */
        int min_buffer_;        /* minimum guarantee buffer */

        int enable_shared_buf_; /* enable shared buffer or not (static buffer) */
        int shared_buf_id_;     /* index of shared buffer to use */
        double alpha_;     /* alpha for DT buffer allocation */

        int pkt_tot_;   /* total number of packets */
        int pkt_drop_;  /* total number of packets dropped by the port */
        int pkt_drop_ecn_;     /* total number of packets dropped when the queue length < ECN marking threshold */

        PacketQueue *q_;        /* underlying (usually) FIFO queue */

	Tcl_Channel shared_qlen_tchan_;        /* place to write shared buffer occupancy records */
	Tcl_Channel port_qlen_tchan_;  /* place to write per-port buffer occupancy records */

        static int shared_buf_lim_[SHARED_BUFFER_NUM];  /* shared buffer sizes */
        static int shared_buf_len_[SHARED_BUFFER_NUM];  /* shared buffer occupancies in bytes*/
        static int shared_buf_mem_[SHARED_BUFFER_NUM];  /* number of members (queue/port) belonging to a shared buffer */
};

#endif
