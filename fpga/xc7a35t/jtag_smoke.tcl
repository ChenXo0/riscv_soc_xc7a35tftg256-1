set script_dir [file normalize [file dirname [info script]]]
set bitfile    [file normalize [file join $script_dir top.bit]]
set ltxfile    [file normalize [file join $script_dir top.ltx]]

set hw_host [string trim [expr {[info exists ::env(HW_HOST)] ? $::env(HW_HOST) : "192.168.0.171"}]]
set hw_port [string trim [expr {[info exists ::env(HW_PORT)] ? $::env(HW_PORT) : "51235"}]]
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd [expr {[info exists ::env(HW_SERVER_CMD)] ? $::env(HW_SERVER_CMD) : "E:/vivado/2025.1/Vivado/bin/hw_server.bat"}]

set CONTROL_ADDR 0xF0000000
set STATUS_ADDR  0xF0000004
set VERSION_ADDR 0xF0000008
set MEM_BASE     0x80000000

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

if {![file exists $bitfile]} {
    error "Bitstream not found: $bitfile"
}

if {![file exists $ltxfile]} {
    error "Debug probes not found: $ltxfile"
}

puts "HW_SERVER_CMD=$hw_server_cmd"
puts "HW_SERVER_URL=$hw_url"

catch {exec taskkill /IM hw_server.exe /F}
catch {exec taskkill /IM cs_server.exe /F}
catch {exec $hw_server_cmd -s tcp::${hw_port} &}
after 5000

open_hw_manager
connect_hw_server -url $hw_url
open_hw_target

set hw_dev [lindex [get_hw_devices] 0]
if {$hw_dev eq ""} {
    error "No hardware device found"
}

current_hw_device $hw_dev
set_property PROBES.FILE $ltxfile $hw_dev
set_property FULL_PROBES.FILE $ltxfile $hw_dev
set_property PROGRAM.FILE $bitfile $hw_dev
program_hw_devices $hw_dev
refresh_hw_device -update_hw_probes true $hw_dev

set hw_ilas [get_hw_ilas -quiet -of_objects $hw_dev]
set hw_axis [get_hw_axis -quiet -of_objects $hw_dev]
puts "HW_ILAS_COUNT=[llength $hw_ilas]"
puts "HW_AXIS_COUNT=[llength $hw_axis]"

set hw_axi [get_hw_axi_handle]
refresh_hw_axi $hw_axi
reset_hw_axi $hw_axi

puts "VERSION=[run_axi_read $hw_axi $VERSION_ADDR]"
puts "STATUS_BEFORE=[run_axi_read $hw_axi $STATUS_ADDR]"

puts "Holding CPU reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000000
puts "CONTROL_AFTER_HOLD=[run_axi_read $hw_axi $CONTROL_ADDR]"

set mem0 [run_axi_read $hw_axi $MEM_BASE]
puts [format {MEM[%08X]=%s} $MEM_BASE $mem0]
run_axi_write $hw_axi $MEM_BASE $mem0
set mem0_rdback [run_axi_read $hw_axi $MEM_BASE]
puts [format {MEM_RDBACK[%08X]=%s} $MEM_BASE $mem0_rdback]
set mem1_addr [format 0x%08X [expr {$MEM_BASE + 4}]]
set mem2_addr [format 0x%08X [expr {$MEM_BASE + 8}]]
set mem1 [run_axi_read $hw_axi $mem1_addr]
set mem2 [run_axi_read $hw_axi $mem2_addr]
puts [format {MEM[%s]=%s} $mem1_addr $mem1]
puts [format {MEM[%s]=%s} $mem2_addr $mem2]
run_axi_write $hw_axi $mem1_addr $mem1
puts [format {MEM_RDBACK[%s]=%s} $mem1_addr [run_axi_read $hw_axi $mem1_addr]]

puts "Releasing CPU reset..."
run_axi_write $hw_axi $CONTROL_ADDR 00000001
puts "CONTROL_AFTER_RELEASE=[run_axi_read $hw_axi $CONTROL_ADDR]"

for {set i 0} {$i < 8} {incr i} {
    puts [format {STATUS[%d]=%s} $i [run_axi_read $hw_axi $STATUS_ADDR]]
}

close_hw_manager
exit 0
