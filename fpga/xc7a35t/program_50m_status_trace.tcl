set hw_host "192.168.0.171"
set hw_port "51235"
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd "E:/vivado/2025.1/Vivado/bin/hw_server.bat"
set bitfile "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.bit"

proc dump_status {tag hw_dev} {
    puts "STATUS_TAG=$tag"
    puts "  DONE_PIN=[get_property {REGISTER.CONFIG_STATUS.BIT14_DONE_PIN} $hw_dev]"
    puts "  DONE_INT=[get_property {REGISTER.CONFIG_STATUS.BIT13_DONE_INTERNAL_SIGNAL_STATUS} $hw_dev]"
    puts "  EOS=[get_property {REGISTER.CONFIG_STATUS.BIT04_END_OF_STARTUP_(EOS)_STATUS} $hw_dev]"
    puts "  GWE=[get_property {REGISTER.CONFIG_STATUS.BIT06_GWE_STATUS} $hw_dev]"
    puts "  GTS=[get_property {REGISTER.CONFIG_STATUS.BIT05_GTS_CFG_B_STATUS} $hw_dev]"
    puts "  PLL_LOCK=[get_property {REGISTER.CONFIG_STATUS.BIT02_PLL_LOCK_STATUS} $hw_dev]"
    puts "  IR_DONE=[get_property {REGISTER.IR.BIT5_DONE} $hw_dev]"
    puts "  BOOT_STATUS=[get_property REGISTER.BOOT_STATUS $hw_dev]"
    puts "  CONFIG_STATUS=[get_property REGISTER.CONFIG_STATUS $hw_dev]"
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
set_property PARAM.FREQUENCY 3000000 $tgt
close_hw_target
open_hw_target
set hw_dev [lindex [get_hw_devices] 0]
current_hw_device $hw_dev
refresh_hw_device -update_hw_probes false $hw_dev
dump_status BEFORE $hw_dev
set_property PROGRAM.FILE $bitfile $hw_dev
program_hw_devices $hw_dev
puts "PROGRAM_DONE"
refresh_hw_device -update_hw_probes false $hw_dev
dump_status AFTER_0S $hw_dev
after 1000
refresh_hw_device -update_hw_probes false $hw_dev
dump_status AFTER_1S $hw_dev
after 2000
refresh_hw_device -update_hw_probes false $hw_dev
dump_status AFTER_3S $hw_dev
close_hw_manager
exit 0
