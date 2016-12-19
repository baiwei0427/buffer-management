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
host_delay = 0.000019   #18us
ports = 32
packet_size = 8960
static_buf_pkt = 1111   #10MB buffer for NIC
enable_shared_buf = 'true'
num_shared_buf = 4
shared_buf_size = 4 * 1024 * 1024   #4MB
dt_alpha = 4
port_ecn_thresh = 80
sp_ecn_thresh = 4 * 1024 * 1024 - 2.5 * 1024 * 1024 / dt_alpha
sp_ecn_schemes = ['true', 'false']
enable_dctcp = 'true'
init_window = 16
max_window = 125
rto_min = 0.005
flow_tot = 200000
connections_per_pair = 10
loads = [0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
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
        if ecn_scheme == 'true':    #enable per-service-pool ECN
            scheme += '_sp'

        # directory name: [scheme]_load_[load]
        dir_name = '%s_load_%d' % (scheme, int(load * 100))
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
            + str(port_ecn_thresh) + ' '\
            + str(sp_ecn_thresh) + ' '\
            + str(ecn_scheme) + ' '\
            + str(enable_dctcp) + ' '\
            + str(init_window) + ' '\
            + str(max_window) + ' '\
            + str(rto_min) + ' '\
            + str(flow_tot) + ' '\
            + str(connections_per_pair) + ' '\
            + str(load) + ' '\
            + str(flow_cdf) + ' '\
            + str(mean_flow_size) + ' '\
			+ str('./' + dir_name + '/flow.tr') + '  >'\
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
