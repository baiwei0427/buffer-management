#include <stdio.h>
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

void MyRED::enque(Packet* p)
{
        hdr_flags* hf = hdr_flags::access(p);
        int pktSize = hdr_cmn::access(p)->size();
        int qlen_bytes = pktSize + q_->byteLength();
        int thresh_bytes = thresh_ * mean_pktsize_;

        if (qlen_bytes > qlim_ * mean_pktsize_)
        {
                drop(p);
		if (debug_)
			printf("qlen %d > qlim %d\n", qlen_bytes, qlim_ * mean_pktsize_);
                return;
        }

        if (qlen_bytes > thresh_bytes && hf->ect())
        {
                hf->ce() = 1;
                if (debug_)
                        printf("qlen %d > thresh %d\n", qlen_bytes, thresh_bytes);
        }

        q_->enque(p);
}

Packet* MyRED::deque()
{
        return (q_->deque());
}
