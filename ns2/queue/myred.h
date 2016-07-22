#ifndef ns_my_red_h
#define ns_my_red_h

#include "queue.h"

class MyRED : public Queue
{
public:
        MyRED()
        {
                q_ = new PacketQueue();
                thresh_ = 65;
                mean_pktsize_ = 1500;
                debug_ = 0;

                bind("thresh_", &thresh_);
                bind("mean_pktsize_", &mean_pktsize_);
                bind_bool("debug_", &debug_);
        }
        ~MyRED()
        {
                delete q_;
        }

protected:
        void enque(Packet*);
	Packet* deque();

        int thresh_;
        int mean_pktsize_;
        int debug_;
        PacketQueue *q_;        /* underlying (usually) FIFO queue */
};

#endif
