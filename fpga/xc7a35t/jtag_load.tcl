proc usage {} {
    puts "Usage: vivado -mode batch -source jtag_load.tcl -tclargs <mem_file> ?base_addr? ?status_poll_count?"
    puts "  mem_file: one 32-bit hex word per line"
    puts "  base_addr: default 0x80000000"
    puts "  status_poll_count: default 8"
}

if {$argc < 1} {
    usage
    exit 2
}

set mem_file [lindex $argv 0]
set base_addr 0x80000000
set status_poll_count 8
if {$argc >= 2} {
    set base_addr [lindex $argv 1]
}
if {$argc >= 3} {
    set status_poll_count [lindex $argv 2]
}

set CONTROL_ADDR 0xF0000000
set STATUS_ADDR  0xF0000004
set VERSION_ADDR 0xF0000008
set hw_host [string trim [expr {[info exists ::env(HW_HOST)] ? $::env(HW_HOST) : "192.168.0.171"}]]
set hw_port [string trim [expr {[info exists ::env(HW_PORT)] ? $::env(HW_PORT) : "51235"}]]
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd [expr {[info exists ::env(HW_SERVER_CMD)] ? $::env(HW_SERVER_CMD) : "E:/vivado/2025.1/Vivado/bin/hw_server.bat"}]

proc connect_hw_server_auto {} {
    if {[info exists ::env(HW_SERVER_URL)] && [string trim $::env(HW_SERVER_URL)] ne ""} {
        connect_hw_server -url [string trim $::env(HW_SERVER_URL)]
    } else {
        connect_hw_server -url $::hw_url
    }
}

proc get_hw_axi_handle {} {
    set devs [get_hw_devices]
    if {[llength $devs] < 1} {
        error "No hardware devices found"
    }
    current_hw_device [lindex $devs 0]
    refresh_hw_device -update_hw_probes true [current_hw_device]
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

if {![file exists $mem_file]} {
    error "Memory image not found: $mem_file"
}

puts "HW_SERVER_CMD=$hw_server_cmd"
puts "HW_SERVER_URL=$hw_url"

catch {exec taskkill /IM hw_server.exe /F}
catch {exec taskkill /IM cs_server.exe /F}
catch {exec $hw_server_cmd -s tcp::${hw_port} &}
after 5000

open_hw_manager
connect_hw_server_auto
open_hw_target

set hw_axi [get_hw_axi_handle]
refresh_hw_axi $hw_axi
reset_hw_axi $hw_axi

puts "VERSION=[run_axi_read $hw_axi $VERSION_ADDR]"
puts "Holding CPU in reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000000

set fp [open $mem_file r]
set line_num 0
while {[gets $fp line] >= 0} {
    set word [string trim $line]
    if {$word eq ""} {
        continue
    }
    if {![regexp {^[0-9A-Fa-f]{8}$} $word]} {
        error "Invalid word at line [expr {$line_num + 1}]: '$word'"
    }
    set addr_hex [format 0x%08X [expr {$base_addr + ($line_num * 4)}]]
    run_axi_write $hw_axi $addr_hex [string toupper $word]
    set rdback [run_axi_read $hw_axi $addr_hex]
    if {[string toupper $rdback] ne [string toupper $word]} {
        error "Verify failed at address $addr_hex: wrote [string toupper $word], read $rdback"
    }
    incr line_num
}
close $fp

puts "Releasing CPU reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000001

for {set i 0} {$i < $status_poll_count} {incr i} {
    puts [format {STATUS[%d]=%s} $i [run_axi_read $hw_axi $STATUS_ADDR]]
}

close_hw_manager
exit 0
