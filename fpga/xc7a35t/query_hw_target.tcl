set hw_url "TCP:192.168.0.171:51235"
open_hw_manager
connect_hw_server -url $hw_url
open_hw_target
set tgt [current_hw_target]
puts "CURRENT_HW_TARGET=$tgt"
report_property $tgt
close_hw_manager
exit 0
