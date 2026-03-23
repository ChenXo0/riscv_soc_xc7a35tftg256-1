proc usage {} {
    puts "Usage: vivado -mode batch -source jtag_load_and_console_tx_v1.tcl -tclargs <mem0> <addr0> ?<mem1> <addr1> ...?"
}

if {$argc < 2 || ($argc % 2) != 0} {
    usage
    exit 2
}

set CONTROL_ADDR 0xF0000000
set STATUS_ADDR  0xF0000004
set VERSION_ADDR 0xF0000008
set CONSOLE_ADDR 0xF000000C

set hw_host [string trim [expr {[info exists ::env(HW_HOST)] ? $::env(HW_HOST) : "192.168.0.171"}]]
set hw_port [string trim [expr {[info exists ::env(HW_PORT)] ? $::env(HW_PORT) : "51235"}]]
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd [expr {[info exists ::env(HW_SERVER_CMD)] ? $::env(HW_SERVER_CMD) : "E:/vivado/2025.1/Vivado/bin/hw_server.bat"}]
set jtag_freq_hz [string trim [expr {[info exists ::env(JTAG_FREQ_HZ)] ? $::env(JTAG_FREQ_HZ) : "1000000"}]]
set max_burst_words [expr {[info exists ::env(MAX_BURST_WORDS)] ? int($::env(MAX_BURST_WORDS)) : 64}]
set poll_ms [expr {[info exists ::env(POLL_MS)] ? int($::env(POLL_MS)) : 5}]
set max_idle_loops [expr {[info exists ::env(MAX_IDLE_LOOPS)] ? int($::env(MAX_IDLE_LOOPS)) : 8000}]
if {$max_burst_words < 1} {
    set max_burst_words 1
}

proc connect_hw_server_auto {} {
    if {[info exists ::env(HW_SERVER_URL)] && [string trim $::env(HW_SERVER_URL)] ne ""} {
        connect_hw_server -url [string trim $::env(HW_SERVER_URL)]
    } else {
        connect_hw_server -url $::hw_url
    }
}

proc apply_hw_target_frequency {} {
    if {$::jtag_freq_hz eq ""} {
        return
    }

    set tgt [current_hw_target]
    if {$tgt eq ""} {
        return
    }

    puts "JTAG_FREQ_HZ=$::jtag_freq_hz"
    if {[catch {set_property PARAM.FREQUENCY $::jtag_freq_hz $tgt} freq_msg]} {
        puts "JTAG_FREQ_SET_WARN=$freq_msg"
        return
    }

    close_hw_target
    open_hw_target
}

proc get_hw_axi_handle {} {
    set devs [get_hw_devices]
    if {[llength $devs] < 1} {
        error "No hardware devices found"
    }

    current_hw_device [lindex $devs 0]
    refresh_hw_device -update_hw_probes false [current_hw_device]
    set axis [get_hw_axis -quiet -of_objects [current_hw_device]]
    if {[llength $axis] < 1} {
        error "No hw_axi instances found in the programmed design"
    }

    return [lindex $axis 0]
}

proc run_axi_write {hw_axi address data} {
    set txn_name [format "wr_%08X" $address]
    create_hw_axi_txn $txn_name $hw_axi -type write -address $address -len 1 -data [list $data] -force
    run_hw_axi [get_hw_axi_txns $txn_name]
    delete_hw_axi_txn [get_hw_axi_txns $txn_name]
}

proc run_axi_read {hw_axi address} {
    set txn_name [format "rd_%08X" $address]
    create_hw_axi_txn $txn_name $hw_axi -type read -address $address -len 1 -force
    run_hw_axi [get_hw_axi_txns $txn_name]
    set data [string toupper [string trim [get_property DATA [get_hw_axi_txns $txn_name]] "{} "]]
    delete_hw_axi_txn [get_hw_axi_txns $txn_name]
    return $data
}

proc flush_burst {hw_axi burst_base_name burst_words_name line_num_name} {
    upvar 1 $burst_base_name burst_base
    upvar 1 $burst_words_name burst_words
    upvar 1 $line_num_name line_num

    if {[llength $burst_words] == 0} {
        return
    }

    set txn_name [format "wr_%08X_len%d" $burst_base [llength $burst_words]]
    create_hw_axi_txn $txn_name $hw_axi -type write -address [format 0x%08X $burst_base] -len [llength $burst_words] -data $burst_words -force
    run_hw_axi [get_hw_axi_txns $txn_name]
    delete_hw_axi_txn [get_hw_axi_txns $txn_name]

    incr line_num [llength $burst_words]
    set burst_words {}
}

proc load_mem_file {hw_axi mem_file base_addr} {
    if {![file exists $mem_file]} {
        error "Memory image not found: $mem_file"
    }

    puts "Loading $mem_file -> $base_addr"
    set fp [open $mem_file r]
    set line_num 0
    set burst_words {}
    set burst_base 0

    while {[gets $fp line] >= 0} {
        set word [string trim $line]
        if {$word eq ""} {
            continue
        }
        if {[llength $burst_words] == 0} {
            set burst_base [expr {$base_addr + ($line_num * 4)}]
        }
        lappend burst_words [string toupper $word]
        if {[llength $burst_words] >= $::max_burst_words} {
            flush_burst $hw_axi burst_base burst_words line_num
        }
    }
    close $fp
    flush_burst $hw_axi burst_base burst_words line_num
    puts "Loaded words=$line_num from $mem_file"
}

proc console_decode {raw_hex} {
    scan $raw_hex %x value
    set overflow [expr {($value >> 31) & 1}]
    set valid    [expr {($value >> 30) & 1}]
    set level    [expr {($value >> 16) & 0x3FFF}]
    set ch       [expr {$value & 0xFF}]
    return [list $overflow $valid $level $ch]
}

catch {close_hw_manager}
catch {disconnect_hw_server}
catch {exec taskkill /IM hw_server.exe /F}
catch {exec taskkill /IM cs_server.exe /F}
catch {exec $hw_server_cmd -s tcp::${hw_port} &}
after 5000

open_hw_manager
connect_hw_server_auto
open_hw_target
apply_hw_target_frequency
catch {set_msg_config -id {Labtoolstcl 44-481} -suppress}
catch {set_msg_config -id {Labtools 27-1347} -suppress}
catch {set_msg_config -id {Labtools 27-1974} -suppress}

set hw_axi [get_hw_axi_handle]
refresh_hw_axi $hw_axi
reset_hw_axi $hw_axi

puts "VERSION=[run_axi_read $hw_axi $VERSION_ADDR]"
puts "Holding CPU in reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000000

for {set i 0} {$i < $argc} {incr i 2} {
    set mem_file [lindex $argv $i]
    set base_addr [lindex $argv [expr {$i + 1}]]
    load_mem_file $hw_axi $mem_file $base_addr
}

run_axi_write $hw_axi $CONSOLE_ADDR 80000000
puts "Releasing CPU reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000001

set idle_loops 0
set total_chars 0
set overflow_seen 0

while {$max_idle_loops < 0 || $idle_loops < $max_idle_loops} {
    lassign [console_decode [run_axi_read $hw_axi $CONSOLE_ADDR]] overflow valid level ch

    if {$overflow} {
        set overflow_seen 1
    }

    if {$valid} {
        puts -nonewline [format %c $ch]
        flush stdout
        incr total_chars
        set idle_loops 0
    } else {
        incr idle_loops
        after $poll_ms
    }
}

if {$total_chars > 0} {
    puts ""
}
puts "TOTAL_CHARS=$total_chars"
puts "OVERFLOW_SEEN=$overflow_seen"
puts "STATUS_END=[run_axi_read $hw_axi $STATUS_ADDR]"

close_hw_manager
exit 0
