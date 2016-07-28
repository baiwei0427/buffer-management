source "tcp-traffic-gen.tcl"

set ns [new Simulator]
set link_rate 100; #100Gbps
set mean_link_delay 0.0000002; #0.2us
set host_delay 0.000012; #12us

set fattree_k 16
set topology_x 1

set flowlog [open flow.tr w]
set debug_mode 1
set sim_start [clock seconds]
set flow_tot 200000; #total number of flows to generate
set flow_gen 0; #the number of flows that have been generated
set flow_fin 0; #the number of flows that have finished
set packet_size 8960; #Jumbo packet (9KB)
set source_alg Agent/TCP/FullTcp/Sack
set switch_alg DCTCP

set flow_cdf CDF_dctcp.tcl
set mean_flow_size 1711250

set num_pairs 40
set connections_per_pair 20
set load 0.5; # load of edge links

set buffer_size 300; # 300 MTU = 2.7MB
set rto_min 0.001; # 1ms
set ecn_thresh 60; # 60 MTU = 540KB, BDP = 625KB

################ Shared Buffer ##################
set avg_port_buf 250000; # 250KB
set edge_port [expr int($fattree_k / 2 + $fattree_k / 2 * $topology_x)]
set edge_shared_buf [expr $edge_port * $avg_port_buf]
set core_shared_buf [expr $fattree_k * $avg_port_buf]

puts "shared buffer of edge switches ($edge_port ports): $edge_shared_buf"
puts "shared buffer of aggregation/core switches ($fattree_k ports): $core_shared_buf"

################## TCP #########################
Agent/TCP set ecn_ 1
Agent/TCP set old_ecn_ 1
Agent/TCP set dctcp_ true
Agent/TCP set dctcp_g_ 0.0625
Agent/TCP set windowInit_ 16
Agent/TCP set packetSize_ $packet_size
Agent/TCP set window_ 1000
Agent/TCP set slow_start_restart_ true
Agent/TCP set tcpTick_ 0.000001; # 1us should be enough
Agent/TCP set minrto_ $rto_min
Agent/TCP set rtxcur_init_ $rto_min; # initial RTO
Agent/TCP set maxrto_ 64
Agent/TCP set numdupacks_ 3; # dup ACK threshold
Agent/TCP set windowOption_ 0

Agent/TCP/FullTcp set nodelay_ true; # disable Nagle
Agent/TCP/FullTcp set segsize_ $packet_size
Agent/TCP/FullTcp set segsperack_ 1; # ACK frequency
Agent/TCP/FullTcp set interval_ 0.000006; #delayed ACK interval

################ Queue #########################
Queue set limit_ $buffer_size
Queue/RED set bytes_ false
Queue/RED set queue_in_bytes_ true
Queue/RED set mean_pktsize_ [expr $packet_size + 40]
Queue/RED set setbit_ true
Queue/RED set gentle_ false
Queue/RED set q_weight_ 1.0
Queue/RED set mark_p_ 1.0
Queue/RED set thresh_ $ecn_thresh
Queue/RED set maxthresh_ $ecn_thresh

Queue/DCTCP set thresh_ $ecn_thresh
Queue/DCTCP set mean_pktsize_ [expr $packet_size + 40]
Queue/DCTCP set enable_shared_buf_ true
Queue/DCTCP set shared_buf_id_ -1
Queue/DCTCP set alpha_ 2
Queue/DCTCP set debug_ false

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
set topology_servers [expr int($fattree_k * $fattree_k * $fattree_k * $topology_x / 4)]
set topology_spt [expr int($fattree_k * $topology_x / 2)] ; # servers per ToR (spt)
set topology_edges [expr int($fattree_k * $fattree_k / 2)]
set topology_aggrs [expr int($fattree_k * $fattree_k / 2)]
set topology_cores [expr int($fattree_k * $fattree_k / 4)]

puts "Servers: $topology_servers"
puts "Servers per ToR: $topology_spt"
puts "Edge Switches: $topology_edges"
puts "Aggregation Switches: $topology_aggrs"
puts "Core Switches: $topology_cores"

######### Servers #########
for {set i 0} {$i < $topology_servers} {incr i} {
        set s($i) [$ns node]
}

######### Edge Switches #########
for {set i 0} {$i < $topology_edges} {incr i} {
        set edge($i) [$ns node]
}

######### Aggregation Switches #########
for {set i 0} {$i < $topology_aggrs} {incr i} {
        set aggr($i) [$ns node]
}

######### Core Switches #########
for {set i 0} {$i < $topology_cores} {incr i} {
        set core($i) [$ns node]
}

######### Links from Servers to Edge Switches #########
for {set i 0} {$i < $topology_servers} {incr i} {
        set j [expr $i / $topology_spt] ; # ToR ID
        $ns duplex-link $s($i) $edge($j) [set link_rate]Gb [expr $host_delay + $mean_link_delay] $switch_alg

        ######### configure shared buffer for edge to server links #######
        set L [$ns link $edge($j) $s($i)]
        set q [$L set queue_]
        set buf_id $j
        $q set shared_buf_id_ $buf_id
        $q set-shared-buffer $buf_id $edge_shared_buf
        $q register
}

######### Links from Edge to Aggregation Switches #########
for {set i 0} {$i < $topology_edges} {incr i} {

        set pod [expr $i / ($fattree_k / 2)] ; # pod ID
        set start [expr $pod * $fattree_k / 2]
        set end [expr $start + $fattree_k / 2]

        for {set j $start} {$j < $end} {incr j} {
                $ns duplex-link $edge($i) $aggr($j) [set link_rate]Gb [expr $mean_link_delay] $switch_alg

                ######### configure shared buffer for edge to aggregation links #######
                set L [$ns link $edge($i) $aggr($j)]
                set q [$L set queue_]
                set buf_id $i
                $q set shared_buf_id_ $buf_id
                $q set-shared-buffer $buf_id $edge_shared_buf
                $q register

                ######## configure shared buffer for aggregation to edge links ########
                set L [$ns link $aggr($j) $edge($i)]
                set q [$L set queue_]
                set buf_id [expr $j + $fattree_k * $fattree_k / 2]
                $q set shared_buf_id_ $buf_id
                $q set-shared-buffer $buf_id $core_shared_buf
                $q register
        }
}

######### Links from Aggregation to Core Switches #########
for {set i 0} {$i < $topology_aggrs} {incr i} {

        set index [expr $i % ($fattree_k / 2)] ; # index in pod
        set start [expr $index * $fattree_k / 2]
        set end [expr $start + $fattree_k / 2]

        for {set j $start} {$j < $end} {incr j} {
                $ns duplex-link $aggr($i) $core($j) [set link_rate]Gb [expr $mean_link_delay] $switch_alg

                ######### configure shared buffer for aggregation to core links #######
                set L [$ns link $aggr($i) $core($j)]
                set q [$L set queue_]
                set buf_id [expr $i + $fattree_k * $fattree_k / 2]
                $q set shared_buf_id_ $buf_id
                $q set-shared-buffer $buf_id $core_shared_buf
                $q register

                ######### configure shared buffer for core to aggregation links #######
                set L [$ns link $core($j) $aggr($i)]
                set q [$L set queue_]
                set buf_id [expr $j + $fattree_k * $fattree_k]
                $q set shared_buf_id_ $buf_id
                $q set-shared-buffer $buf_id $core_shared_buf
                $q register
        }
}

######## print information of shared buffer switches #######
$q print

#############  Agents ################
set lambda [expr ($link_rate * $load * 1000000000)/($mean_flow_size * 8.0 / $packet_size * ($packet_size + 40))]
puts "Edge link average utilization: $load"
puts "Arrival: Poisson with inter-arrival [expr 1 / $lambda * 1000] ms"
puts "Average flow size: $mean_flow_size bytes"
puts "Setting up connections ..."; flush stdout

set snd_interval [expr $topology_servers / $num_pairs]

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
