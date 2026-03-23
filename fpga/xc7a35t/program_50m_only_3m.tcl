set hw_host "192.168.0.171"
set hw_port "51235"
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd "E:/vivado/2025.1/Vivado/bin/hw_server.bat"
set bitfile "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.bit"
set ltxfile "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.ltx"

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
set_property PROBES.FILE $ltxfile $hw_dev
set_property FULL_PROBES.FILE $ltxfile $hw_dev
set_property PROGRAM.FILE $bitfile $hw_dev
program_hw_devices $hw_dev
puts "PROGRAM_DONE"
close_hw_manager
exit 0
