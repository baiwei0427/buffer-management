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
topology_spt = 16
topology_tors = 8
topology_spines = 8

flow_tot = 100000
num_pairs = 127
connections_per_pair = 3
core_loads = [0.4, 0.45, 0.5, 0.55, 0.6, 0.65, 0.7, 0.75, 0.8, 0.85, 0.9]
flow_cdf = 'CDF_dctcp.tcl'
mean_flow_size = 1711250

enable_dctcp = 'true'
init_window = 20
max_window = 150
packet_size = 8960
rto_min = 0.005

static_buf_pkt = 1111
enable_shared_buf = 'true'
shared_buf_ports = 8
shared_buf_size = 3 * 1024 * 1024
dt_alpha = 4
reserve_buf_size = 128 * 1024

port_ecn_thresh = 80
sp_ecn_schemes = ['true', 'false']
sp_ecn_min_thresh = shared_buf_size - (1.72 * 1024 * 1024 - reserve_buf_size) / dt_alpha - 600 * 1024
sp_ecn_max_thresh = shared_buf_size - (1.72 * 1024 * 1024 - reserve_buf_size) / dt_alpha - 0 * 1024
sp_ecn_max_prob = 0.04

ns_path = '/home/wei/buffer_management/ns-allinone-2.35/ns-2.35/ns'
sim_script = 'spine_empirical.tcl'

topology_x = float(topology_spt) / topology_spines
print 'Oversubscription ratio ' + str(topology_x)

for ecn_scheme in sp_ecn_schemes:
	for core_load in core_loads:
		scheme = 'spine' #spine leaf topology

		if enable_dctcp == 'true':
			scheme += '_dctcp'
		else:
			scheme += '_tcp'

		if enable_shared_buf == 'true': #enable shared buffer
			scheme += '_shared'
		else:
			scheme += '_static'

		if ecn_scheme == 'true':    #enable per-service-pool ECN
			if sp_ecn_min_thresh < sp_ecn_max_thresh:   #RED-like probability marking
				scheme += '_bcc_red'
			else:   #DCTCP-like cut off marking
				scheme += '_bcc_cut_off'

        # directory name: [scheme]_K_[ECN thresh]_load_[load]
		dir_name = '%s_K_%d_load_%d' % (scheme, port_ecn_thresh, int(core_load * 100))
		# transfer core load to edge load
		edge_load = core_load / topology_x

		#Simulation command
		cmd = ns_path + ' ' + sim_script + ' '\
			+ str(link_rate) + ' '\
			+ str(mean_link_delay) +' '\
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
			+ str(enable_dctcp) + ' '\
			+ str(init_window) + ' '\
			+ str(max_window) + ' '\
			+ str(packet_size) + ' '\
			+ str(rto_min) + ' '\
			+ str(static_buf_pkt) + ' '\
			+ str(enable_shared_buf) + ' '\
			+ str(shared_buf_ports) + ' '\
			+ str(shared_buf_size) + ' '\
			+ str(dt_alpha) + ' '\
			+ str(reserve_buf_size) + ' '\
			+ str(port_ecn_thresh) + ' '\
			+ str(ecn_scheme) + ' '\
			+ str(sp_ecn_min_thresh) + ' '\
			+ str(sp_ecn_max_thresh) + ' '\
			+ str(sp_ecn_max_prob) + ' '\
			+ str('./' + dir_name + '/flow.tr') + '  >'\
			+ str('./' + dir_name + '/logFile.tr')
		print cmd
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
