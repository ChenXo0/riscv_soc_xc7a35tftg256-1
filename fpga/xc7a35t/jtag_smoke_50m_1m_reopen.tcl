set hw_host "192.168.0.171"
set hw_port "51235"
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd "E:/vivado/2025.1/Vivado/bin/hw_server.bat"
set bitfile "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.bit"
set ltxfile "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.ltx"
set CONTROL_ADDR 0xF0000000
set STATUS_ADDR  0xF0000004
set VERSION_ADDR 0xF0000008

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

catch {close_hw_manager}
catch {disconnect_hw_server}
catch {exec taskkill /IM hw_server.exe /F}
catch {exec taskkill /IM cs_server.exe /F}
catch {exec $hw_server_cmd -s tcp::${hw_port} &}
after 5000

open_hw_manager
connect_hw_server -url $hw_url
open_hw_target
set tgt [current_hw_target]
set_property PARAM.FREQUENCY 1000000 $tgt
close_hw_target
open_hw_target
set hw_dev [lindex [get_hw_devices] 0]
current_hw_device $hw_dev
refresh_hw_device -update_hw_probes false $hw_dev
set_property PROBES.FILE $ltxfile $hw_dev
set_property FULL_PROBES.FILE $ltxfile $hw_dev
set_property PROGRAM.FILE $bitfile $hw_dev
program_hw_devices $hw_dev
puts "PROGRAM_DONE"
after 500
close_hw_target
after 500
open_hw_target
set tgt [current_hw_target]
set_property PARAM.FREQUENCY 1000000 $tgt
set hw_dev [lindex [get_hw_devices] 0]
current_hw_device $hw_dev
set_property PROBES.FILE $ltxfile $hw_dev
set_property FULL_PROBES.FILE $ltxfile $hw_dev
refresh_hw_device -update_hw_probes true $hw_dev
set hw_ilas [get_hw_ilas -quiet -of_objects $hw_dev]
set hw_axis [get_hw_axis -quiet -of_objects $hw_dev]
puts "HW_ILAS_COUNT=[llength $hw_ilas]"
puts "HW_AXIS_COUNT=[llength $hw_axis]"
set hw_axi [lindex $hw_axis 0]
refresh_hw_axi $hw_axi
reset_hw_axi $hw_axi
puts "VERSION=[run_axi_read $hw_axi $VERSION_ADDR]"
for {set i 0} {$i < 5} {incr i} {
    puts [format {LOOP_%d_STATUS=%s} $i [run_axi_read $hw_axi $STATUS_ADDR]]
    after 1000
}
close_hw_manager
exit 0
