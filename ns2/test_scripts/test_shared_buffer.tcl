set ns [new Simulator]

set port1_senders 8
set port2_senders 2
set ecn_thresh 80000; #The ECN marking threshold (pkts)
set dwrr_quantum 1500; #The quantum (weight) of the queue
set queue_alpha 4
set buf_id 0
set buf_size 270000; #270KB
set marking_schme 0; #per-queue ECN
set buffer_scheme 2; #DT algorithm

set RTT 0.0001
set DCTCP_g_ 0.0625
set ackRatio 1
set packetSize 1460
set lineRate 10Gb

set simulationTime 0.04
set throughputSamplingInterval 0.0004

Agent/TCP set windowInit_ 16
Agent/TCP set ecn_ 0
Agent/TCP set old_ecn_ 0
Agent/TCP set dctcp_ false
Agent/TCP set dctcp_g_ $DCTCP_g_
Agent/TCP set packetSize_ $packetSize
Agent/TCP set window_ 1256
Agent/TCP set slow_start_restart_ false
Agent/TCP set minrto_ 0.01 ; # minRTO = 10ms
Agent/TCP set windowOption_ 0
Agent/TCP/FullTcp set segsize_ $packetSize
Agent/TCP/FullTcp set segsperack_ $ackRatio;
Agent/TCP/FullTcp set spa_thresh_ 3000;
Agent/TCP/FullTcp set interval_ 0.04 ; #delayed ACK interval = 40ms

Queue set limit_ 1000

Queue/DWRR set queue_num_ 8
Queue/DWRR set mean_pktsize_ [expr $packetSize+40]
Queue/DWRR set port_thresh_ $ecn_thresh
Queue/DWRR set marking_scheme_ $marking_schme
Queue/DWRR set estimate_round_alpha_ 0.75
Queue/DWRR set estimate_quantum_alpha_ 0.75
Queue/DWRR set estimate_round_idle_interval_bytes_ 1500
Queue/DWRR set estimate_quantum_interval_bytes_ 1500
Queue/DWRR set estimate_quantum_enable_timer_ false
Queue/DWRR set link_capacity_ $lineRate
Queue/DWRR set buffer_scheme_ $buffer_scheme
Queue/DWRR set shared_buffer_id_ $buf_id
Queue/DWRR set alpha_ 2
Queue/DWRR set debug_ true

set mytracefile [open mytracefile.tr w]
$ns trace-all $mytracefile
set throughputfile [open throughputfile.tr w]
set port1_tot_qlenfile [open port1_tot_qlenfile.tr w]
set port2_tot_qlenfile [open port2_tot_qlenfile.tr w]

proc finish {} {
    global ns mytracefile throughputfile port1_tot_qlenfile port2_tot_qlenfile
    $ns flush-trace
    close $mytracefile
    close $throughputfile
    close $port1_tot_qlenfile
    close $port2_tot_qlenfile
    exit 0
}

set switch [$ns node]
set receiver1 [$ns node]
set receiver2 [$ns node]

$ns simplex-link $switch $receiver1 $lineRate [expr $RTT/4] DWRR
$ns simplex-link $receiver1 $switch $lineRate [expr $RTT/4] DropTail
$ns simplex-link $switch $receiver2 $lineRate [expr $RTT/4] DWRR
$ns simplex-link $receiver2 $switch $lineRate [expr $RTT/4] DropTail

set L [$ns link $switch $receiver1]
set q [$L set queue_]
$q attach-total $port1_tot_qlenfile
for {set i 0} {$i<$port1_senders} {incr i} {
    $q set-quantum $i $dwrr_quantum
    $q set-ecn-thresh $i $ecn_thresh
    $q set-alpha $i $queue_alpha
}
$q set-buffer $buf_id $buf_size


set L [$ns link $switch $receiver2]
set q [$L set queue_]
$q attach-total $port2_tot_qlenfile
for {set i 0} {$i<$port2_senders} {incr i} {
    $q set-quantum $i $dwrr_quantum
    $q set-ecn-thresh $i $ecn_thresh
    $q set-alpha $i $queue_alpha
}

#Senders to receiver 1 (port 1)
for {set i 0} {$i<$port1_senders} {incr i} {
    set n1($i) [$ns node]
    $ns duplex-link $n1($i) $switch $lineRate [expr $RTT/4] DropTail
	set tcp1($i) [new Agent/TCP/FullTcp/Sack]
	set sink1($i) [new Agent/TCP/FullTcp/Sack]
	$tcp1($i) set serviceid_ $i
	$sink1($i) listen

	$ns attach-agent $n1($i) $tcp1($i)
    $ns attach-agent $receiver1 $sink1($i)
	$ns connect $tcp1($i) $sink1($i)

	set ftp1($i) [new Application/FTP]
	$ftp1($i) attach-agent $tcp1($i)
	$ftp1($i) set type_ FTP
	$ns at [expr 0.0] "$ftp1($i) start"
}

#Senders to receiver 2 (port 2)
for {set i 0} {$i<$port2_senders} {incr i} {
    set n2($i) [$ns node]
    $ns duplex-link $n2($i) $switch $lineRate [expr $RTT/4] DropTail
	set tcp2($i) [new Agent/TCP/FullTcp/Sack]
	set sink2($i) [new Agent/TCP/FullTcp/Sack]
	$tcp2($i) set serviceid_ $i
	$sink2($i) listen

	$ns attach-agent $n2($i) $tcp2($i)
    $ns attach-agent $receiver2 $sink2($i)
	$ns connect $tcp2($i) $sink2($i)

	set ftp2($i) [new Application/FTP]
	$ftp2($i) attach-agent $tcp2($i)
	$ftp2($i) set type_ FTP
	$ns at [expr $simulationTime/2] "$ftp2($i) start"
}

proc record {} {
    global ns throughputfile throughputSamplingInterval port1_senders port2_senders tcp1 sink1 tcp2 sink2

    #Get the current time
	set now [$ns now]

    #Initialize the output string
    set str $now
    append str ", "

    set bw1 0
    for {set i 0} {$i<$port1_senders} {incr i} {
        set bytes [$sink1($i) set bytes_]
		set bw1 [expr $bw1+$bytes]
		$sink1($i) set bytes_ 0
	}
	append str " "
	append str [expr int($bw1/$throughputSamplingInterval*8/1000000)];	#throughput in Mbps
	append str ", "

	set bw2 0
	for {set i 0} {$i<$port2_senders} {incr i} {
		set bytes [$sink2($i) set bytes_]
		set bw2 [expr $bw2+$bytes]
		$sink2($i) set bytes_ 0
	}
	append str " "
	append str [expr int($bw2/$throughputSamplingInterval*8/1000000)];	#throughput in Mbps

	puts $throughputfile $str

	#Set next callback time
	$ns at [expr $now+$throughputSamplingInterval] "record"

}

$ns at 0.0 "record"
$ns at [expr $simulationTime] "finish"
$ns run
