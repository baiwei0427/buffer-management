source "tcp-traffic-gen.tcl"

set ns [new Simulator]

if {$argc != 29} {
    puts "wrong number of arguments $argc"
    exit 0
}

#basic setting
set link_rate [lindex $argv 0]
set mean_link_delay [lindex $argv 1]
set host_delay [lindex $argv 2]
set ports [lindex $argv 3]; #number of switch ports
set packet_size [lindex $argv 4];       #MTU - IP header - TCP header

#switch buffer management
set static_buf_pkt [lindex $argv 5];    #static buffer size in packets
set enable_shared_buf [lindex $argv 6]
set num_shared_buf [lindex $argv 7];    #number of shared buffers of a chip
set shared_buf_size [lindex $argv 8];   #size of a shared buffer in bytes
set dt_alpha [lindex $argv 9];  #alpha for dynamic threshold (DT) algorithm
set reserve_buf_size [lindex $argv 10];  #per-port static reserved buffer

#ECN marking
set port_ecn_thresh [lindex $argv 11];   #per-port ECN marking threshold
set sp_ecn_min_thresh [lindex $argv 12];        #per-service-pool ECN min marking threshold
set sp_ecn_max_thresh [lindex $argv 13];        #per-service-pool ECN max marking threshold
set sp_ecn_max_prob [lindex $argv 14];  #per-service-pool ECN max marking probability
set enable_sp_ecn [lindex $argv 15];    #enable per-service-pool ECN marking

#transport setting
set enable_dctcp [lindex $argv 16];
set init_window [lindex $argv 17]
set max_window [lindex $argv 18]
set rto_min [lindex $argv 19]

#traffic
set receivers [lindex $argv 20]; #number of receivers, the rest hosts are senders
set flow_tot [lindex $argv 21]; #total number of flows to run
set connections_per_pair [lindex $argv 22]
set load [lindex $argv 23]
set flow_cdf [lindex $argv 24]
set mean_flow_size [lindex $argv 25]

#log file
set flowlog [open [lindex $argv 26] w]
set port_qlen_log [open [lindex $argv 27] w]
set shared_qlen_log [open [lindex $argv 28] w]

#print all arguments
puts "link speed: $link_rate Gbps"
puts "mean link delay: [expr $mean_link_delay * 1000000] us"
puts "host delay: [expr $host_delay * 1000000] us"
puts "number of switch ports: $ports"
puts "packet size: $packet_size"
puts "static switch buffer size: $static_buf_pkt packets"
puts "enable shared buffer management: $enable_shared_buf"
puts "number of share buffers: $num_shared_buf"
puts "size of a share buffer: $shared_buf_size bytes"
puts "alpha for dynamic threshold algorithm: $dt_alpha"
puts "size of per-port reserved buffer: $reserve_buf_size bytes"
puts "per-port ECN marking threshold: $port_ecn_thresh packets"
puts "per-service-pool ECN min marking threshold: $sp_ecn_min_thresh bytes"
puts "per-service-pool ECN max marking threshold: $sp_ecn_max_thresh bytes"
puts "per-service-pool ECN max marking probability: $sp_ecn_max_prob"
puts "enable per-service-pool ECN marking: $enable_sp_ecn"
puts "enable DCTCP: $enable_dctcp"
puts "TCP initial window: $init_window"
puts "TCP maximum window: $max_window"
puts "TCP minimum RTO: [expr $rto_min * 1000000] us"
puts "number of receivers: $receivers, number of senders: [expr $ports - $receivers]"
puts "total number of flows to run: $flow_tot"
puts "number of connections per pair: $connections_per_pair"
puts "average network utilization: $load"
puts "flow size CDF file: $flow_cdf"
puts "average flow size: $mean_flow_size bytes"
puts "flow log file [lindex $argv 24]"
puts "port buffer log file [lindex $argv 25]"
puts "shared buffer log file [lindex $argv 26]"

set debug_mode 1
set sim_start [clock seconds]
set flow_gen 0; #the number of flows that have been generated
set flow_fin 0; #the number of flows that have finished
set switch_alg DCTCP
set source_alg Agent/TCP/FullTcp/Sack

#set packet_size 8960; #Jumbo packet (9KB)

#set rto_min 0.005; # 5ms

#set flow_cdf CDF_dctcp.tcl
#set mean_flow_size 1711250
#set flow_cdf CDF_vl2.tcl
#set mean_flow_size 12658199

################## TCP #########################
Agent/TCP set dctcp_ $enable_dctcp
Agent/TCP set ecn_ 1
Agent/TCP set old_ecn_ 1
Agent/TCP set dctcp_g_ 0.0625
Agent/TCP set windowInit_ $init_window
Agent/TCP set maxcwnd_ $max_window
Agent/TCP set window_ $max_window
Agent/TCP set packetSize_ $packet_size
Agent/TCP set slow_start_restart_ true
Agent/TCP set tcpTick_ 0.000001; # 1us should be enough
Agent/TCP set minrto_ $rto_min
Agent/TCP set rtxcur_init_ $rto_min; # initial RTO
Agent/TCP set maxrto_ 64
Agent/TCP set windowOption_ 0

Agent/TCP/FullTcp set nodelay_ true; # disable Nagle
Agent/TCP/FullTcp set segsize_ $packet_size
Agent/TCP/FullTcp set segsperack_ 1; # ACK frequency
Agent/TCP/FullTcp set interval_ 0.000006; #delayed ACK interval

################ Queue #########################
Queue set limit_ $static_buf_pkt

Queue/DCTCP set debug_ false
Queue/DCTCP set mean_pktsize_ [expr $packet_size + 40]

Queue/DCTCP set enable_shared_buf_ $enable_shared_buf
Queue/DCTCP set alpha_ $dt_alpha
Queue/DCTCP set reserve_buf_lim_ $reserve_buf_size
Queue/DCTCP set pkt_tot_ 0
Queue/DCTCP set pkt_drop_ 0
Queue/DCTCP set pkt_drop_ecn_ 0

Queue/DCTCP set thresh_ $port_ecn_thresh
Queue/DCTCP set enable_sp_ecn_ $enable_sp_ecn
Queue/DCTCP set sp_min_thresh_ $sp_ecn_min_thresh
Queue/DCTCP set sp_max_thresh_ $sp_ecn_max_thresh
Queue/DCTCP set sp_max_prob_ $sp_ecn_max_prob

Queue/DCTCP set enable_buffer_ecn_ false

######################## Topoplgy #########################
set switch [$ns node]

set qid 0
set ports_per_buffer [expr $ports / $num_shared_buf]

for {set i 0} {$i < $ports} {incr i} {
        set s($i) [$ns node]
        $ns duplex-link $s($i) $switch [set link_rate]Gb [expr $host_delay + $mean_link_delay] $switch_alg

        ######### configure shared buffer for edge to server links #######
        set L [$ns link $switch $s($i)]
        set q [$L set queue_]
        $q set switch_id_ [expr $i / $ports_per_buffer]
        $q set-shared-buffer [expr $i / $ports_per_buffer] $shared_buf_size
        $q set port_id_ $qid
        $q register

        if {$i == 0} {
                $q trace-port-qlen $port_qlen_log
                $q trace-shared-qlen $shared_qlen_log
        }

        set queues($qid) $q
        incr qid
}

######## print information of shared buffer switches #######
$q print

#############  Agents ################
set lambda [expr ($link_rate * $load * 1000000000)/($mean_flow_size * 8.0 / $packet_size * ($packet_size + 40))]
puts "Edge link average utilization: $load"
puts "Arrival: Poisson with inter-arrival [expr 1 / $lambda * 1000] ms"
puts "Average flow size: $mean_flow_size bytes"
puts "Setting up connections ..."; flush stdout

#s[0] ... s[receivers - 1] are receivers
#s[receivers] .... s[ports - 1] are senders
for {set j 0} {$j < $receivers} {incr j} {
        for {set i $receivers} {$i < $ports} {incr i} {
                ##sender s(i), receiver s(j)
                puts -nonewline "($i $j) "
                set agtagr($i,$j) [new Agent_Aggr_pair]
                $agtagr($i,$j) setup $s($i) $s($j) "$i $j" $connections_per_pair "TCP_pair" $source_alg
                ## Note that RNG seed should not be zero
                $agtagr($i,$j) set_PCarrival_process [expr $lambda / ($ports - $receivers)] $flow_cdf [expr 17*$i+1244*$j] [expr 33*$i+4369*$j]
                $agtagr($i,$j) attach-logfile $flowlog

                $ns at 0.1 "$agtagr($i,$j) warmup 0.5 $packet_size"
                $ns at 1 "$agtagr($i,$j) init_schedule"
        }
        flush stdout
}

puts "Initial agent creation done"
puts "Simulation started!"
$ns run
