set dcp_path [expr {$argc >= 1 ? [lindex $argv 0] : "E:/fpga/repo/riscv_soc/fpga/xc7a35t/build/top_routed.dcp"}]

proc count_pins_by_pattern {pattern} {
    return [llength [get_pins -quiet -hier -regexp $pattern]]
}

open_checkpoint $dcp_path

puts "DCP=$dcp_path"

set dwidth_cells [get_cells -quiet -hier -filter {NAME =~ *axi_mem_dwidth* || REF_NAME =~ axi_dwidth_converter*}]
puts "AXI_DWIDTH_CELLS=[llength $dwidth_cells]"
foreach c $dwidth_cells {
    puts "AXI_DWIDTH_CELL=$c REF=[get_property REF_NAME $c]"
}

set cdc_cells [get_cells -quiet -hier -filter {NAME =~ *axi_cdc_buffer* || REF_NAME =~ axi_clock_converter* || REF_NAME =~ axi_register_slice*}]
puts "AXI_CDC_LIKE_CELLS=[llength $cdc_cells]"
foreach c $cdc_cells {
    puts "AXI_CDC_CELL=$c REF=[get_property REF_NAME $c]"
}

set mig_wdata_pins [lsort [get_pins -quiet -hier -filter {NAME =~ *u_ddr/u_ddr3*s_axi_wdata*}]]
set mig_wstrb_pins [lsort [get_pins -quiet -hier -filter {NAME =~ *u_ddr/u_ddr3*s_axi_wstrb*}]]
set mig_awaddr_pins [lsort [get_pins -quiet -hier -filter {NAME =~ *u_ddr/u_ddr3*s_axi_awaddr*}]]
set mig_araddr_pins [lsort [get_pins -quiet -hier -filter {NAME =~ *u_ddr/u_ddr3*s_axi_araddr*}]]

puts "MIG_WDATA_PINS=[llength $mig_wdata_pins]"
puts "MIG_WSTRB_PINS=[llength $mig_wstrb_pins]"
puts "MIG_AWADDR_PINS=[llength $mig_awaddr_pins]"
puts "MIG_ARADDR_PINS=[llength $mig_araddr_pins]"
puts "MIG_WDATA_SAMPLE=[lrange $mig_wdata_pins 0 7]"
puts "MIG_WSTRB_SAMPLE=[lrange $mig_wstrb_pins 0 7]"
puts "MIG_AWADDR_SAMPLE=[lrange $mig_awaddr_pins 0 7]"
puts "MIG_ARADDR_SAMPLE=[lrange $mig_araddr_pins 0 7]"

set cdc_wdata_pat {.*u_mem_cdc.*/outport_wdata_o\[.*\]}
set cdc_wstrb_pat {.*u_mem_cdc.*/outport_wstrb_o\[.*\]}
set cdc_awaddr_pat {.*u_mem_cdc.*/outport_awaddr_o\[.*\]}

puts "CDC_WDATA_PINS=[count_pins_by_pattern $cdc_wdata_pat]"
puts "CDC_WSTRB_PINS=[count_pins_by_pattern $cdc_wstrb_pat]"
puts "CDC_AWADDR_PINS=[count_pins_by_pattern $cdc_awaddr_pat]"

close_design
exit 0
