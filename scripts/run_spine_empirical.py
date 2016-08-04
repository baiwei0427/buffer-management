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
mean_link_delay = 0.000001
host_delay = 0.000018
topology_spt = 24
topology_tors = 32
topology_spines = 8

flow_tot = 200000
num_pairs = 128
connections_per_pair = 3
load_arr = [0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9]
flow_cdf = 'CDF_dctcp.tcl'
mean_flow_size = 1711250

enable_ecn = 1
enable_dctcp = 1
init_window = 25
packet_size = 8960
rto_min = 0.005

switch_alg = 'DCTCP'
static_port_pkt = 1111
shared_port_bytes = 8 * 1024 * 1024 / 32
enable_shared_buf = 1
dt_alpha = 1
ecn_thresh = 90

ns_path = '/home/wei/buffer_management/ns-allinone-2.35/ns-2.35/ns'
sim_script = 'spine_empirical.tcl'

topology_x = float(topology_spt) / topology_spines
print 'Oversubscription ratio ' + str(topology_x)

for load in load_arr:
	# directory name: load_[load]
	directory_name = 'load_%d' % int(load * 100)
	# transfer core load to edge load
	edge_load = load / topology_x

	#Simulation command
	cmd = ns_path + ' ' + sim_script + ' '\
			+ str(link_rate) + ' '\
			+ str(mean_link_delay) + ' '\
			+ str(host_delay) + ' '\
			+ str(topology_spt) + ' '\
			+ str(topology_tors) + ' '\
			+ str(topology_spines) + ' '\
			+ str(flow_tot) + ' '\
			+ str(num_pairs) + ' '\
			+ str(connections_per_pair) + ' '\
			+ str(edge_load) + ' '\
			+ str(flow_cdf) + ' '\
			+ str(mean_flow_size) + ' '\
			+ str(enable_ecn) + ' '\
			+ str(enable_dctcp) + ' '\
			+ str(init_window) + ' '\
			+ str(packet_size) + ' '\
			+ str(rto_min) + ' '\
			+ str(switch_alg) + ' '\
			+ str(static_port_pkt) + ' '\
			+ str(shared_port_bytes) + ' '\
			+ str(enable_shared_buf) + ' '\
			+ str(dt_alpha) + ' '\
			+ str(ecn_thresh) + ' '\
			+str('./' + directory_name + '/flow.tr') + '  >'\
			+str('./' + directory_name + '/logFile.tr')
	q.put([cmd, directory_name])

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
