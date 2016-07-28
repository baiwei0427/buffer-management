source "tcp-traffic-gen.tcl"

set ns [new Simulator]
set link_rate 100; #100Gbps
set mean_link_delay 0.0000002; #0.2us
set host_delay 0.000012; #12us
set ports 32
set connections_per_pair 20
set load 0.9

set static_buf_pkt 333; # 333 MTU = 3MB
set shared_buf 8388608; # 8MB
set ecn_thresh 60; # 60 MTU = 540KB, BDP = 625KB

set flowlog [open singleswitch_flow.tr w]
set debug_mode 1
set sim_start [clock seconds]
set flow_tot 100000; #total number of flows to generate
set flow_gen 0; #the number of flows that have been generated
set flow_fin 0; #the number of flows that have finished
set packet_size 8960; #Jumbo packet (9KB)
set source_alg Agent/TCP/FullTcp/Sack
set switch_alg DCTCP
set rto_min 0.005; # 1ms

set flow_cdf CDF_dctcp.tcl
set mean_flow_size 1711250

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
Queue set limit_ $static_buf_pkt
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
Queue/DCTCP set alpha_ 1
Queue/DCTCP set debug_ false

######################## Topoplgy #########################
set switch [$ns node]

for {set i 0} {$i < $ports} {incr i} {
        set s($i) [$ns node]
        $ns duplex-link $s($i) $switch [set link_rate]Gb [expr $host_delay + $mean_link_delay] $switch_alg

        ######### configure shared buffer for edge to server links #######
        set L [$ns link $switch $s($i)]
        set q [$L set queue_]
        $q set shared_buf_id_ 0
        $q set-shared-buffer 0 $shared_buf
        $q register
}

######## print information of shared buffer switches #######
$q print

#############  Agents ################
set lambda [expr ($link_rate * $load * 1000000000)/($mean_flow_size * 8.0 / $packet_size * ($packet_size + 40))]
puts "Edge link average utilization: $load"
puts "Arrival: Poisson with inter-arrival [expr 1 / $lambda * 1000] ms"
puts "Average flow size: $mean_flow_size bytes"
puts "Setting up connections ..."; flush stdout

for {set j 0} {$j < $ports} {incr j} {
        for {set i 0} {$i < $ports} {incr i} {
                if {$j != $i} {
                        puts -nonewline "($i $j) "
                        set agtagr($i,$j) [new Agent_Aggr_pair]
                        $agtagr($i,$j) setup $s($i) $s($j) "$i $j" $connections_per_pair "TCP_pair" $source_alg
                        ## Note that RNG seed should not be zero
                        $agtagr($i,$j) set_PCarrival_process [expr $lambda / ($ports - 1)] $flow_cdf [expr 17*$i+1244*$j] [expr 33*$i+4369*$j]
                        $agtagr($i,$j) attach-logfile $flowlog

                        $ns at 0.1 "$agtagr($i,$j) warmup 0.5 $packet_size"
                        $ns at 1 "$agtagr($i,$j) init_schedule"
                }
        }
        puts ""
        flush stdout
}

puts "Initial agent creation done"
puts "Simulation started!"
$ns run
