#ifndef ns_my_red_h
#define ns_my_red_h

#include "queue.h"

/* MyRED: a simple version of Random Early Detection (RED) for DCTCP-style ECN marking */
#define NUM_SWITCH 128  /* maximum number of switches (shared buffers) */
#define NUM_PORT_PER_SWITCH 32 /* maximum number of ports per switch */

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
        void port_mark(Packet*); /* per port ECN marking */
        void sp_mark(Packet*);  /*per service pool ECN marking */
        void buffer_mark(Packet*);      /* buffer-aware ECN marking */
        void trace_shared_qlen();       /* trace the occupancy of the shared buffer */
        void trace_port_qlen(); /* trace per-port buffer occupancy */

        int debug_;     /* print necessary debug information or not */

        int port_id_;   /* switch port ID. Within the same switch, different ports have different IDs. */
        int switch_id_; /* switch ID */

        int thresh_;    /* ECN marking threshold in packet */
        int mean_pktsize_;      /* packet size in bytes */

        int enable_buffer_ecn_;        /* enable buffer-aware ECN */
        double headroom_;      /* headroom parameter */

        int enable_sp_ecn_; /* enable per service pool ECN marking */
        int sp_min_thresh_;     /* min marking threshold (in bytes) for per service-pool ECN marking */
        int sp_max_thresh_;     /* max marking threshold (in bytes) for per service-pool ECN marking */
        double sp_max_prob_;    /* max marking probability for per service-pool ECN marking */

        int enable_shared_buf_; /* enable shared buffer or not (static buffer) */
        double alpha_;     /* alpha for DT buffer allocation */
        int reserve_buf_lim_;   /* static reserved buffer in bytes */
        int reserve_buf_len_;   /* occupancy of static reserved buffer */

        int pkt_tot_;   /* total number of packets */
        int pkt_drop_;  /* total number of packets dropped by the port */
        int pkt_drop_ecn_;     /* total number of packets dropped when the queue length < ECN marking threshold */

        PacketQueue *q_;        /* underlying (usually) FIFO queue */

	Tcl_Channel shared_qlen_tchan_;        /* place to write shared buffer occupancy records */
	Tcl_Channel port_qlen_tchan_;  /* place to write per-port buffer occupancy records */

        static int port_len_[NUM_SWITCH * NUM_PORT_PER_SWITCH];      /* per port buffer occupancies */
        static int shared_buf_lim_[NUM_SWITCH];  /* per switch shared buffer sizes */
        static int shared_buf_len_[NUM_SWITCH];  /* per switch shared buffer occupancies */
        static int shared_buf_mem_[NUM_SWITCH];  /* number of members (queue/port) belonging to a shared buffer */
};

#endif
