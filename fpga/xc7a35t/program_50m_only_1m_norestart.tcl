set hw_url  "TCP:192.168.0.171:51235"
set bitfile "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.bit"
set ltxfile "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.ltx"
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
close_hw_manager
exit 0
