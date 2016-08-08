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
        void ecn_mark(Packet*); /* perform ECN marking */

        int thresh_;    /* ECN marking threshold in packet */
        int mean_pktsize_;      /* packet size in bytes */
        int debug_;     /* print necessary debug information or not */
        int enable_dynamic_ecn_;        /* enable dynamic ECN marking threshold */
        int ecn_headroom_;      /* headroom buffer in bytes */
        int enable_shared_buf_; /* enable shared buffer or not (static buffer) */
        int shared_buf_id_;     /* index of shared buffer to use */
        double alpha_;     /* alpha for DT buffer allocation */
        int pkt_tot_;   /* total number of packets */
        int pkt_drop_;  /* total number of packets dropped by the port */
        int pkt_drop_ecn_;     /* total number of packets dropped when the queue length < ECN marking threshold */
        PacketQueue *q_;        /* underlying (usually) FIFO queue */

        static int shared_buf_lim_[SHARED_BUFFER_NUM];  /* shared buffer sizes */
        static int shared_buf_len_[SHARED_BUFFER_NUM];  /* shared buffer occupancies in bytes*/
        static int shared_buf_mem_[SHARED_BUFFER_NUM];  /* number of members (queue/port) belonging to a shared buffer */
};

#endif
