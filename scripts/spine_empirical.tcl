source "tcp-traffic-gen.tcl"

set ns [new Simulator]
set sim_start [clock seconds]

if {$argc != 29} {
    puts "wrong number of arguments $argc"
    exit 0
}

#### Topology
set link_rate [lindex $argv 0]; #link rate (Gbps)
set mean_link_delay [lindex $argv 1]; #link propagation + processing delay
set host_delay [lindex $argv 2]; #processing delay at end host
set topology_spt [lindex $argv 3]; #number of servers per ToR
set topology_tors [lindex $argv 4]; #number of ToR switches
set topology_spines [lindex $argv 5]; #number of spine (core) switches

#### Traffic
set flow_tot [lindex $argv 6]; #total number of flows to generate
set num_pairs [lindex $argv 7]; #number of senders that a host can receive traffic from
set connections_per_pair [lindex $argv 8]; #the number of parallel connections for each sender-receiver pair
set edge_load [lindex $argv 9]; #average utilization of server-ToR (edge) links
set flow_cdf [lindex $argv 10]; #file of flow size CDF
set mean_flow_size [lindex $argv 11]; #average size of the above distribution

#### Transport settings options
set enable_dctcp [lindex $argv 12]
set init_window [lindex $argv 13]; #TCP initial window in packets
set max_window [lindex $argv 14]; #maximum TCP congestion window
set packet_size [lindex $argv 15]; #packet size in bytes
set rto_min [lindex $argv 16]

#### Switch buffer management
set static_buf_pkt [lindex $argv 17]; #static buffer size in packets (per port)
set enable_shared_buf [lindex $argv 18]; #enable shared buffer or not
set shared_buf_ports [lindex $argv 19]; #number of ports per shared buffer
set shared_buf_size [lindex $argv 20]; #size of shared buffer in bytes
set dt_alpha [lindex $argv 21];  #alpha for dynamic threshold (DT) algorithm
set reserve_buf_size [lindex $argv 22];  #per-port static reserved buffer

#### ECN marking
set port_ecn_thresh [lindex $argv 23]; #per-port ECN marking threshold (in pkts)
set enable_sp_ecn [lindex $argv 24]; #enable per-service-pool ECN marking
set sp_ecn_min_thresh [lindex $argv 25]; #per-service-pool ECN min marking threshold (in pkts)
set sp_ecn_max_thresh [lindex $argv 26]; #per-service-pool ECN max marking threshold (in pkts)
set sp_ecn_max_prob [lindex $argv 27]; #per-service-pool ECN max marking probability

### result file
set flowlog [open [lindex $argv 28] w]

### print all arguments
puts "link speed: $link_rate Gbps"
puts "mean link delay: [expr $mean_link_delay * 1000000] us"
puts "host delay: [expr $host_delay * 1000000] us"
puts "number of servers per ToR: $topology_spt"
puts "number of ToR (leaf) switches: $topology_tors"
puts "number of Core (spine) switches: $topology_spines"

puts "total number of flows: $flow_tot"
puts "number of senders for each receiver: $num_pairs"
puts "number of TCP connections for eahc host pair: $connections_per_pair"
puts "average utilization of edge links: $edge_load"
puts "flow size CDF file: $flow_cdf"
puts "average flow size: $mean_flow_size bytes"

puts "enable DCTCP: $enable_dctcp"
puts "TCP initial window: $init_window"
puts "TCP maximum window: $max_window"
puts "TCP MSS size: $packet_size bytes"
puts "TCP minimum RTO: [expr $rto_min * 1000000] us"

puts "static queue length: $static_buf_pkt packets"
puts "enable shared buffer management: $enable_shared_buf"
puts "number of ports attached to a shared buffer pool: $shared_buf_ports"
puts "size of a shared buffer pool: $shared_buf_size bytes"
puts "alpha for dynamic threshold algorithm: $dt_alpha"
puts "size of per-port reserved buffer: $reserve_buf_size bytes"

puts "per-port ECN marking threshold: $port_ecn_thresh packets"
puts "enable per-service-pool ECN marking: $enable_sp_ecn"
puts "per-service-pool ECN min marking threshold: $sp_ecn_min_thresh bytes"
puts "per-service-pool ECN max marking threshold: $sp_ecn_max_thresh bytes"
puts "per-service-pool ECN max marking probability: $sp_ecn_max_prob"

puts "FCT result file: [lindex $argv 28]"

set debug_mode 1
set flow_gen 0; #the number of flows that have been generated
set flow_fin 0; #the number of flows that have finished
set source_alg Agent/TCP/FullTcp/Sack
set switch_alg DCTCP

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

################ Multipathing ###########################
$ns rtproto DV
Agent/rtProto/DV set advertInterval [expr 2 * $flow_tot]
Node set multiPath_ 1
Classifier/MultiPath set perflow_ true
Classifier/MultiPath set debug_ false
#if {$debug_mode != 0} {
#        Classifier/MultiPath set debug_ true
#}

######################## Topoplgy #########################
if {[expr $topology_spt % $shared_buf_ports] != 0 ||
    [expr $topology_spines % $shared_buf_ports] != 0 ||
    [expr $topology_tors % $shared_buf_ports] != 0} {
        puts "Invalid input"
        exit 0
}

set topology_servers [expr $topology_spt * $topology_tors]; #number of servers in total
set num_buf_leaf_host [expr $topology_spt / $shared_buf_ports * $topology_tors]; #number of buffers shared by egress ports from leaf switches to hosts
set num_buf_leaf_spine [expr $topology_spines / $shared_buf_ports * $topology_tors]; #number of buffers shared by egress ports from leaf switches to core switches
set num_buf_spine_leaf [expr $topology_tors / $shared_buf_ports * $topology_spines]; #number of buffers shared by egress ports from core switches to leaf switches

puts "number of buffers shared by ports from leaf switches to hosts: $num_buf_leaf_host"
puts "number of buffers shared by ports from leaf switches to core switches: $num_buf_leaf_spine"
puts "number of buffers shared by ports from spine switches to leaf switches: $num_buf_spine_leaf"

for {set i 0} {$i < $topology_servers} {incr i} {
        set s($i) [$ns node]
}

for {set i 0} {$i < $topology_tors} {incr i} {
        set tor($i) [$ns node]
}

for {set i 0} {$i < $topology_spines} {incr i} {
        set spine($i) [$ns node]
}

set qid 0

############ Edge links ##############
for {set i 0} {$i < $topology_servers} {incr i} {
        set j [expr $i / $topology_spt]
        $ns duplex-link $s($i) $tor($j) [set link_rate]Gb [expr $host_delay + $mean_link_delay] $switch_alg

        ######### configure shared buffer for ToR to host links #######
        set L [$ns link $tor($j) $s($i)]
        set q [$L set queue_]
        set buf_id [expr $i / $shared_buf_ports]
        $q set shared_buf_id_ $buf_id
        $q set-shared-buffer $buf_id $shared_buf_size
        $q register
        set queues($qid) $q
        incr qid

        puts "Link from ToR $j to server $i attached to buffer $buf_id"
}

############ Core links ##############
for {set i 0} {$i < $topology_tors} {incr i} {
        for {set j 0} {$j < $topology_spines} {incr j} {
                $ns duplex-link $tor($i) $spine($j) [set link_rate]Gb $mean_link_delay $switch_alg

                ######### configure shared buffer for ToR to spine links #######
                set L [$ns link $tor($i) $spine($j)]
                set q [$L set queue_]
                set buf_id [expr ($i * $topology_spines + $j) / $shared_buf_ports + $num_buf_leaf_host]
                $q set shared_buf_id_ $buf_id
                $q set-shared-buffer $buf_id $shared_buf_size
                $q register
                set queues($qid) $q
                incr qid
                puts "Link from ToR $i to Spine $j attached to buffer $buf_id"

                ######## configure shared buffer for spine to ToR links ########
                set L [$ns link $spine($j) $tor($i)]
                set q [$L set queue_]
                set buf_id [expr ($j * $topology_tors + $i) / $shared_buf_ports + $num_buf_leaf_host + $num_buf_leaf_spine]
                $q set shared_buf_id_ $buf_id
                $q set-shared-buffer $buf_id $shared_buf_size
                $q register
                set queues($qid) $q
                incr qid
                puts "Link from Spine $j to ToR $i attached to buffer $buf_id"
        }
}

######## print information of shared buffer switches #######
$q print

#############  Agents ################
set lambda [expr ($link_rate * $edge_load * 1000000000)/($mean_flow_size * 8.0 / $packet_size * ($packet_size + 40))]
puts "Edge link average utilization: $edge_load"
puts "Arrival: Poisson with inter-arrival [expr 1 / $lambda * 1000] ms"
puts "Average flow size: $mean_flow_size bytes"
puts "Setting up connections ..."; flush stdout

set snd_interval [expr $topology_servers / ($num_pairs + 1)]

for {set j 0} {$j < $topology_servers} {incr j} {
        for {set i 1} {$i <= $num_pairs} {incr i} {
                set snd_id [expr ($j + $i * $snd_interval) % $topology_servers]

                if {$j == $snd_id} {
                        puts "Error: $j == $snd_id"
                        flush stdout
                        exit 0
                } else {
                        puts -nonewline "($snd_id $j) "
                        set agtagr($snd_id,$j) [new Agent_Aggr_pair]
                        $agtagr($snd_id,$j) setup $s($snd_id) $s($j) "$snd_id $j" $connections_per_pair "TCP_pair" $source_alg
                        ## Note that RNG seed should not be zero
                        $agtagr($snd_id,$j) set_PCarrival_process [expr $lambda / $num_pairs] $flow_cdf [expr 17*$snd_id+1244*$j] [expr 33*$snd_id+4369*$j]
                        $agtagr($snd_id,$j) attach-logfile $flowlog

                        $ns at 0.1 "$agtagr($snd_id,$j) warmup 0.5 $packet_size"
                        $ns at 1 "$agtagr($snd_id,$j) init_schedule"
                }
        }
        puts ""
        flush stdout
}

puts "Initial agent creation done"
puts "Simulation started!"
$ns run
