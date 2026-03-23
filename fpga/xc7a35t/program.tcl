set script_dir [file normalize [file dirname [info script]]]
set bitfile    [file normalize [file join $script_dir top.bit]]
set ltxfile    [file normalize [file join $script_dir top.ltx]]
set hw_url     [expr {[info exists ::env(HW_SERVER_URL)] ? $::env(HW_SERVER_URL) : "TCP:192.168.0.171:51235"}]

if {![file exists $bitfile]} {
    puts stderr "Bitstream not found: $bitfile"
    exit 1
}

if {![file exists $ltxfile]} {
    puts stderr "Debug probes not found: $ltxfile"
    exit 1
}

open_hw_manager
connect_hw_server -url $hw_url
open_hw_target

set hw_dev [lindex [get_hw_devices] 0]
if {$hw_dev eq ""} {
    puts stderr "No hardware device found"
    exit 1
}

current_hw_device $hw_dev
refresh_hw_device -update_hw_probes false $hw_dev
set_property PROBES.FILE $ltxfile $hw_dev
set_property FULL_PROBES.FILE $ltxfile $hw_dev
set_property PROGRAM.FILE $bitfile $hw_dev
program_hw_devices $hw_dev
refresh_hw_device $hw_dev
set hw_ilas [get_hw_ilas -of_objects $hw_dev]
puts "HW_SERVER_URL=$hw_url"
puts "HW_ILAS_COUNT=[llength $hw_ilas]"
foreach ila $hw_ilas {
    puts "HW_ILA=$ila"
}

quit
