set hw_host "192.168.0.171"
set hw_port "51235"
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd "E:/vivado/2025.1/Vivado/bin/hw_server.bat"
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
puts "CURRENT_HW_TARGET=$tgt"
report_property $tgt
set dev [lindex [get_hw_devices] 0]
puts "CURRENT_HW_DEVICE=$dev"
report_property $dev
close_hw_manager
exit 0
