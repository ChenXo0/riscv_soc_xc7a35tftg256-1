set script_dir [file normalize [file dirname [info script]]]
set soc_dir    [file normalize [file join $script_dir .. .. soc]]
set core_dir   [file normalize [file join $script_dir .. .. core core rv32imsu]]
set build_dir  [file normalize [file join $script_dir build]]
set project_dir [file normalize [file join $build_dir vivado]]
set project_name xc7a35t_jtag_loader
set part_name xc7a35tftg256-1

proc bus_nets {base width} {
    set nets {}
    for {set i 0} {$i < $width} {incr i} {
        lappend nets [format {%s[%d]} $base $i]
    }
    return $nets
}

file mkdir $build_dir

set ddr3_xci [file join $script_dir ip ddr3_ip ddr3_ip.xci]
set fp [open $ddr3_xci r]
set ddr3_xci_text [read $fp]
close $fp
if {![regexp {C_S_AXI_DATA_WIDTH[^\r\n]*>32<} $ddr3_xci_text] &&
    ![regexp {C0_C_S_AXI_DATA_WIDTH[^\r\n]*>32<} $ddr3_xci_text]} {
    puts "WARNING: Unable to prove from ddr3_ip.xci that the MIG AXI width is 32-bit"
}

# NOTE:
# Board-level readback showed 16-byte aliasing when the 32-bit AXI path was
# connected directly into MIG. Even though ddr3_ip.xci exposes 32-bit AXI
# metadata, the implemented path still requires a 32->128 data-width adapter
# to preserve byte-lane / address mapping correctly on this board/MIG config.

set rtl_files [list \
    [file join $script_dir top.v] \
    [file join $script_dir fpga_top.v] \
    [file join $script_dir xc7a35t_ddr_axi.v] \
    [file join $script_dir jtag_axil_bridge.v] \
    [file join $script_dir axi4_cdc.v] \
]
set ip_files [list \
    [file join $script_dir ip ddr3_ip ddr3_ip.xci] \
    [file join $script_dir ip pll_ip pll_ip.xci] \
    [file join $script_dir ip axi_cdc_buffer axi_cdc_buffer.xci] \
]

set soc_files  [lsort [glob -nocomplain [file join $soc_dir *.v]]]
set core_files [lsort [glob -nocomplain [file join $core_dir *.v]]]

create_project -force $project_name $project_dir -part $part_name
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property include_dirs [list $script_dir $soc_dir $core_dir] [current_fileset]

add_files -norecurse $rtl_files
add_files -norecurse $ip_files
if {[llength $soc_files] > 0} {
    add_files -norecurse $soc_files
}
if {[llength $core_files] > 0} {
    add_files -norecurse $core_files
}
add_files -fileset constrs_1 [file join $script_dir xc7a35t.xdc]

source [file join $script_dir xc7a35t_jtag_axi_bd.tcl]

create_ip -name axi_dwidth_converter -vendor xilinx.com -library ip \
          -module_name axi_mem_dwidth
set_property -dict [list \
    CONFIG.PROTOCOL {AXI4} \
    CONFIG.SI_DATA_WIDTH {32} \
    CONFIG.MI_DATA_WIDTH {128} \
    CONFIG.SI_ID_WIDTH {4} \
    CONFIG.ADDR_WIDTH {32} \
    CONFIG.READ_WRITE_MODE {READ_WRITE} \
    CONFIG.ACLK_ASYNC {0}] [get_ips axi_mem_dwidth]

set user_ips [concat [get_ips ddr3_ip] [get_ips pll_ip] [get_ips axi_mem_dwidth] [get_ips axi_cdc_buffer]]

foreach ip $user_ips {
    if {[get_property IS_LOCKED $ip]} {
        puts "Upgrading locked IP: [get_property NAME $ip]"
        upgrade_ip $ip
    }
}

generate_target all $user_ips
export_ip_user_files -of_objects $user_ips -no_script -sync -force -quiet
catch {create_ip_run $user_ips}

set bd_file [get_files -quiet */xc7a35t_jtag_axi_bd.bd]
if {$bd_file eq ""} {
    error "xc7a35t_jtag_axi_bd.bd was not created"
}

generate_target all $bd_file
set wrapper_file [make_wrapper -files $bd_file -top]
if {[llength $wrapper_file] > 1} {
    set wrapper_file [lindex $wrapper_file 0]
}
if {$wrapper_file eq "" || ![file exists $wrapper_file]} {
    error "BD wrapper was not generated"
}
add_files -norecurse $wrapper_file

set_property top top [current_fileset]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

launch_runs synth_1 -jobs 8
wait_on_run synth_1
open_run synth_1 -name synth_1

create_debug_core u_ila_0 ila
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 1 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]

connect_debug_port u_ila_0/clk [get_nets dbg_clk_w]

set_property port_width 32 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [bus_nets dbg_status_w 32]]

create_debug_port u_ila_0 probe
set_property port_width 32 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [bus_nets dbg_ddr_status_w 32]]

create_debug_port u_ila_0 probe
set_property port_width 32 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [bus_nets dbg_axi_awaddr_w 32]]

create_debug_port u_ila_0 probe
set_property port_width 32 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [bus_nets dbg_axi_wdata_w 32]]

create_debug_port u_ila_0 probe
set_property port_width 32 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [bus_nets dbg_axi_araddr_w 32]]

create_debug_port u_ila_0 probe
set_property port_width 32 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [bus_nets dbg_axi_rdata_w 32]]

opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive AggressiveExplore
route_design -directive Explore
phys_opt_design -directive Explore

report_utilization    -file [file join $build_dir top_utilization.rpt]
report_timing_summary -file [file join $build_dir top_timing_summary.rpt]
report_drc            -file [file join $build_dir top_drc.rpt]
write_checkpoint -force [file join $build_dir top_routed.dcp]
write_debug_probes -force [file join $script_dir top.ltx]
write_bitstream  -force [file join $script_dir top.bit]

puts "Generated bitstream: [file join $script_dir top.bit]"
quit
