set hw_host [string trim [expr {[info exists ::env(HW_HOST)] ? $::env(HW_HOST) : "192.168.0.171"}]]
set hw_port [string trim [expr {[info exists ::env(HW_PORT)] ? $::env(HW_PORT) : "51235"}]]
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd [expr {[info exists ::env(HW_SERVER_CMD)] ? $::env(HW_SERVER_CMD) : "E:/vivado/2025.1/Vivado/bin/hw_server.bat"}]
set jtag_freq_hz [string trim [expr {[info exists ::env(JTAG_FREQ_HZ)] ? $::env(JTAG_FREQ_HZ) : "1000000"}]]
set poll_ms [expr {[info exists ::env(POLL_MS)] ? int($::env(POLL_MS)) : 20}]
set max_idle_loops [expr {[info exists ::env(MAX_IDLE_LOOPS)] ? int($::env(MAX_IDLE_LOOPS)) : 250}]
set console_addr 0xF000000C
set status_addr  0xF0000004
set version_addr 0xF0000008

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

proc run_axi_read {hw_axi address} {
    set txn_name [format "rd_%08X" $address]
    create_hw_axi_txn $txn_name $hw_axi -type read -address $address -len 1 -force
    run_hw_axi [get_hw_axi_txns $txn_name]
    set data [string toupper [string trim [get_property DATA [get_hw_axi_txns $txn_name]] "{} "]]
    delete_hw_axi_txn [get_hw_axi_txns $txn_name]
    return $data
}

proc run_axi_write {hw_axi address data} {
    set txn_name [format "wr_%08X" $address]
    create_hw_axi_txn $txn_name $hw_axi -type write -address $address -len 1 -data [list $data] -force
    run_hw_axi [get_hw_axi_txns $txn_name]
    delete_hw_axi_txn [get_hw_axi_txns $txn_name]
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

puts "VERSION=[run_axi_read $hw_axi $version_addr]"
puts "STATUS0=[run_axi_read $hw_axi $status_addr]"
puts "JTAG_CONSOLE_ADDR=[format 0x%08X $console_addr]"
run_axi_write $hw_axi $console_addr 80000000

set idle_loops 0
set total_chars 0
set overflow_seen 0

while {$max_idle_loops < 0 || $idle_loops < $max_idle_loops} {
    lassign [console_decode [run_axi_read $hw_axi $console_addr]] overflow valid level ch

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

close_hw_manager
exit 0
