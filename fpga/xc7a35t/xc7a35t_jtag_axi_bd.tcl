set design_name xc7a35t_jtag_axi_bd

proc pick_supported_ip {pattern} {
    set defs [lsort [get_ipdefs $pattern]]
    if {[llength $defs] == 0} {
        error "Unable to locate supported IP matching $pattern"
    }
    return [lindex $defs end]
}

if {[llength [get_projects -quiet]] == 0} {
    error "xc7a35t_jtag_axi_bd.tcl must be sourced from an open Vivado project"
}

if {[llength [get_bd_designs -quiet $design_name]] != 0} {
    close_bd_design [get_bd_designs $design_name]
    remove_files [get_files -quiet ${design_name}.bd]
}

create_bd_design $design_name
current_bd_design $design_name

set aclk [create_bd_port -dir I -type clk -freq_hz 50000000 aclk]
set aresetn [create_bd_port -dir I -type rst aresetn]
set_property -dict [list CONFIG.POLARITY {ACTIVE_LOW}] $aresetn

set jtag_axi_vlnv [pick_supported_ip xilinx.com:ip:jtag_axi:*]
set axi_pc_vlnv   [pick_supported_ip xilinx.com:ip:axi_protocol_converter:*]

create_bd_cell -type ip -vlnv $jtag_axi_vlnv u_jtag_axi
create_bd_cell -type ip -vlnv $axi_pc_vlnv   u_axi_pc

set_property -dict [list \
    CONFIG.ADDR_WIDTH {32} \
    CONFIG.DATA_WIDTH {32} \
    CONFIG.ID_WIDTH {1} \
    CONFIG.SI_PROTOCOL {AXI4} \
    CONFIG.MI_PROTOCOL {AXI4LITE} \
    CONFIG.TRANSLATION_MODE {2}] [get_bd_cells u_axi_pc]

connect_bd_net $aclk \
    [get_bd_pins u_jtag_axi/aclk] \
    [get_bd_pins u_axi_pc/aclk]

connect_bd_net $aresetn \
    [get_bd_pins u_jtag_axi/aresetn] \
    [get_bd_pins u_axi_pc/aresetn]

connect_bd_intf_net [get_bd_intf_pins u_jtag_axi/M_AXI] [get_bd_intf_pins u_axi_pc/S_AXI]

make_bd_intf_pins_external [get_bd_intf_pins u_axi_pc/M_AXI]
set m_axi_port [lindex [get_bd_intf_ports -quiet] 0]
if {$m_axi_port eq ""} {
    error "Failed to externalize AXI-Lite master interface"
}
set_property name m_axi $m_axi_port

set jtag_space [get_bd_addr_spaces u_jtag_axi/Data]
set ext_seg [get_bd_addr_segs m_axi/Reg]
if {$ext_seg eq ""} {
    error "Unable to find external AXI-Lite slave segment for m_axi"
}
create_bd_addr_seg -range 0xF0001000 -offset 0x00000000 $jtag_space $ext_seg SEG_dbg_bridge

validate_bd_design
save_bd_design
