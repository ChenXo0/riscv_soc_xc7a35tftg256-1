set hw_host "192.168.0.171"
set hw_port "51235"
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd "E:/vivado/2025.1/Vivado/bin/hw_server.bat"
set probes_file [expr {[info exists ::env(PROBES_FILE)] ? $::env(PROBES_FILE) : "E:/fpga/repo/riscv_soc/fpga/xc7a35t/top.ltx"}]
set csv_out [expr {[info exists ::env(CSV_OUT)] ? $::env(CSV_OUT) : "E:/fpga/repo/riscv_soc/fpga/xc7a35t/build/linux_50m_running.csv"}]
set CONTROL_ADDR 0xF0000000
set STATUS_ADDR  0xF0000004
set VERSION_ADDR 0xF0000008

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
set_property PROBES.FILE $probes_file $hw_dev
set_property FULL_PROBES.FILE $probes_file $hw_dev
refresh_hw_device -update_hw_probes true $hw_dev
set hw_ila [lindex [get_hw_ilas -quiet -of_objects $hw_dev] 0]
set hw_axi [lindex [get_hw_axis -quiet -of_objects $hw_dev] 0]
refresh_hw_axi $hw_axi
puts "VERSION=[run_axi_read $hw_axi $VERSION_ADDR]"
puts "STATUS0=[run_axi_read $hw_axi $STATUS_ADDR]"
puts "CONTROL0=[run_axi_read $hw_axi $CONTROL_ADDR]"
run_hw_ila $hw_ila
wait_on_hw_ila $hw_ila
upload_hw_ila_data $hw_ila
set ila_data [lindex [get_hw_ila_data -quiet -of_objects $hw_ila] end]
write_hw_ila_data -csv_file $csv_out $ila_data
puts "ILA_CSV=$csv_out"
close_hw_manager
exit 0
