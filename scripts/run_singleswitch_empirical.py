import threading
import os
import Queue

def worker():
    while True:
        try:
            j = q.get(block = 0)
        except Queue.Empty:
            return
		#Make directory to save results
        os.system('mkdir -p ' + j[1])
        os.system(j[0])

q = Queue.Queue()

link_rate = 100
mean_link_delay = 0.000001  #1us
host_delay = 0.000019   #19us
ports = 32
packet_size = 8960
static_buf_pkt = 1111   #10MB buffer for NIC
enable_shared_buf = 'true'
num_shared_buf = 4
shared_buf_size = 3 * 1024 * 1024   #3MB
dt_alpha = 4
reserve_buf_size = 128 * 1024   #128KB per port
port_ecn_thresh = 111
sp_ecn_min_thresh = shared_buf_size - (2.0 * 1024 * 1024 - reserve_buf_size) / dt_alpha - 500 * 1024
sp_ecn_max_thresh = shared_buf_size - (2.0 * 1024 * 1024 - reserve_buf_size) / dt_alpha
sp_ecn_max_prob = 0.05
sp_ecn_schemes = ['true']
enable_dctcp = 'false'
init_window = 20
max_window = 125
rto_min = 0.005
receivers = 8
flow_tot = 100000
connections_per_pair = 10
loads = [0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9]
flow_cdf = 'CDF_dctcp.tcl'
mean_flow_size = 1711250

ns_path = '/home/wei/buffer_management/ns-allinone-2.35/ns-2.35/ns'
sim_script = 'singleswitch_empirical.tcl'

for ecn_scheme in sp_ecn_schemes:
    for load in loads:
        scheme = ''

        if enable_dctcp == 'true':
            scheme = 'dctcp'
        else:
            scheme = 'tcp'

        if enable_shared_buf == 'true': #enable shared buffer
            scheme += '_shared'
        else:
            scheme += '_static'

        if ecn_scheme == 'true':    #enable per-service-pool ECN
            scheme += '_sp'

        # directory name: [scheme]_K_[ECN thresh]_load_[load]
        dir_name = '%s_K_%d_load_%d' % (scheme, port_ecn_thresh, int(load * 100))
        # simulation command
        cmd = ns_path + ' ' + sim_script + ' '\
            + str(link_rate) + ' '\
            + str(mean_link_delay) + ' '\
            + str(host_delay) + ' '\
            + str(ports) + ' '\
            + str(packet_size) + ' '\
            + str(static_buf_pkt) + ' '\
            + str(enable_shared_buf) + ' '\
            + str(num_shared_buf) + ' '\
            + str(shared_buf_size) + ' '\
            + str(dt_alpha) + ' '\
            + str(reserve_buf_size) + ' '\
            + str(port_ecn_thresh) + ' '\
            + str(sp_ecn_min_thresh) + ' '\
            + str(sp_ecn_max_thresh) + ' '\
            + str(sp_ecn_max_prob) + ' '\
            + str(ecn_scheme) + ' '\
            + str(enable_dctcp) + ' '\
            + str(init_window) + ' '\
            + str(max_window) + ' '\
            + str(rto_min) + ' '\
            + str(receivers) + ' '\
            + str(flow_tot) + ' '\
            + str(connections_per_pair) + ' '\
            + str(load) + ' '\
            + str(flow_cdf) + ' '\
            + str(mean_flow_size) + ' '\
            + str('./' + dir_name + '/flow.tr') + ' '\
            + str('./' + dir_name + '/port_qlen.tr') + ' '\
            + str('./' + dir_name + '/shared_qlen.tr') + ' >'\
            + str('./' + dir_name + '/logFile.tr')
        q.put([cmd, dir_name])

#Create all worker threads
threads = []
number_worker_threads = 20

#Start threads to process jobs
for i in range(number_worker_threads):
	t = threading.Thread(target = worker)
	threads.append(t)
	t.start()

#Join all completed threads
for t in threads:
	t.join()
