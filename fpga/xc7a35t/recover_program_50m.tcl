set hw_host "192.168.0.171"
set hw_port "51235"
set hw_url  [format {TCP:%s:%s} $hw_host $hw_port]
set hw_server_cmd "E:/vivado/2025.1/Vivado/bin/hw_server.bat"
set bitfile "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.bit"
set ltxfile "E:/fpga/repo/riscv_soc/fpga/xc7a35t/backup_50m_20260322/top_50m.ltx"

puts "HW_SERVER_URL=$hw_url"
puts "BITFILE=$bitfile"
puts "LTXFILE=$ltxfile"

catch {close_hw_manager}
catch {disconnect_hw_server}
catch {exec taskkill /IM hw_server.exe /F}
catch {exec taskkill /IM cs_server.exe /F}
catch {exec $hw_server_cmd -s tcp::${hw_port} &}
after 5000

open_hw_manager
connect_hw_server -url $hw_url
open_hw_target

set devs [get_hw_devices]
puts "HW_DEVICES_COUNT=[llength $devs]"
foreach d $devs { puts "HW_DEVICE=$d" }
if {[llength $devs] < 1} {
    error "No hardware devices found"
}

set hw_dev [lindex $devs 0]
current_hw_device $hw_dev
refresh_hw_device -update_hw_probes false $hw_dev
set_property PROBES.FILE $ltxfile $hw_dev
set_property FULL_PROBES.FILE $ltxfile $hw_dev
set_property PROGRAM.FILE $bitfile $hw_dev
program_hw_devices $hw_dev
puts "PROGRAM_DONE"

set refresh_rc [catch {refresh_hw_device -update_hw_probes true $hw_dev} refresh_msg]
puts "REFRESH_PROBES_RC=$refresh_rc"
puts "REFRESH_PROBES_MSG=$refresh_msg"

set hw_ilas [get_hw_ilas -quiet -of_objects $hw_dev]
set hw_axis [get_hw_axis -quiet -of_objects $hw_dev]
puts "HW_ILAS_COUNT=[llength $hw_ilas]"
puts "HW_AXIS_COUNT=[llength $hw_axis]"
foreach ila $hw_ilas { puts "HW_ILA=$ila" }
foreach axi $hw_axis { puts "HW_AXI=$axi" }

close_hw_manager
exit 0
