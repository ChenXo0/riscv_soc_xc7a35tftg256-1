//-----------------------------------------------------------------
// XC7A35T DDR3 AXI wrapper
//-----------------------------------------------------------------
module xc7a35t_ddr_axi
#(
    parameter MEM_BASE_ADDR = 32'h8000_0000
)
(
    // Inputs
     input           clk_200_i
    ,input           rst_n_i
    ,input           inport_awvalid_i
    ,input  [31:0]   inport_awaddr_i
    ,input  [3:0]    inport_awid_i
    ,input  [7:0]    inport_awlen_i
    ,input  [1:0]    inport_awburst_i
    ,input           inport_wvalid_i
    ,input  [31:0]   inport_wdata_i
    ,input  [3:0]    inport_wstrb_i
    ,input           inport_wlast_i
    ,input           inport_bready_i
    ,input           inport_arvalid_i
    ,input  [31:0]   inport_araddr_i
    ,input  [3:0]    inport_arid_i
    ,input  [7:0]    inport_arlen_i
    ,input  [1:0]    inport_arburst_i
    ,input           inport_rready_i

    // Outputs
    ,output          clk_out_o
    ,output          rst_out_o
    ,output          init_calib_complete_o
    ,output          mmcm_locked_o
    ,output [11:0]   device_temp_o
    ,output          inport_awready_o
    ,output          inport_wready_o
    ,output          inport_bvalid_o
    ,output [1:0]    inport_bresp_o
    ,output [3:0]    inport_bid_o
    ,output          inport_arready_o
    ,output          inport_rvalid_o
    ,output [31:0]   inport_rdata_o
    ,output [1:0]    inport_rresp_o
    ,output [3:0]    inport_rid_o
    ,output          inport_rlast_o
    ,output [13:0]   ddr3_addr_o
    ,output [2:0]    ddr3_ba_o
    ,output          ddr3_ras_n_o
    ,output          ddr3_cas_n_o
    ,output          ddr3_we_n_o
    ,output          ddr3_reset_n_o
    ,output [0:0]    ddr3_ck_p_o
    ,output [0:0]    ddr3_ck_n_o
    ,output [0:0]    ddr3_cke_o
    ,output [1:0]    ddr3_dm_o
    ,output [0:0]    ddr3_odt_o
    ,inout  [15:0]   ddr3_dq_io
    ,inout  [1:0]    ddr3_dqs_n_io
    ,inout  [1:0]    ddr3_dqs_p_io
);

wire         ui_clk_w;
wire         ui_clk_sync_rst_w;
wire         mmcm_locked_w;
wire         init_calib_complete_w;
wire [11:0]  device_temp_w;
wire         ui_rst_w;

wire [31:0]  s_axi_awaddr_w = inport_awaddr_i - MEM_BASE_ADDR;
wire [31:0]  s_axi_araddr_w = inport_araddr_i - MEM_BASE_ADDR;

wire [31:0]  mig_axi_awaddr_w;
wire [7:0]   mig_axi_awlen_w;
wire [2:0]   mig_axi_awsize_w;
wire [1:0]   mig_axi_awburst_w;
wire         mig_axi_awlock_w;
wire [3:0]   mig_axi_awcache_w;
wire [2:0]   mig_axi_awprot_w;
wire [3:0]   mig_axi_awqos_w;
wire         mig_axi_awvalid_w;
wire         mig_axi_awready_w;
wire [127:0] mig_axi_wdata_w;
wire [15:0]  mig_axi_wstrb_w;
wire         mig_axi_wlast_w;
wire         mig_axi_wvalid_w;
wire         mig_axi_wready_w;
wire [1:0]   mig_axi_bresp_w;
wire         mig_axi_bvalid_w;
wire         mig_axi_bready_w;
wire [31:0]  mig_axi_araddr_w;
wire [7:0]   mig_axi_arlen_w;
wire [2:0]   mig_axi_arsize_w;
wire [1:0]   mig_axi_arburst_w;
wire         mig_axi_arlock_w;
wire [3:0]   mig_axi_arcache_w;
wire [2:0]   mig_axi_arprot_w;
wire [3:0]   mig_axi_arqos_w;
wire         mig_axi_arvalid_w;
wire         mig_axi_arready_w;
wire [127:0] mig_axi_rdata_w;
wire [1:0]   mig_axi_rresp_w;
wire         mig_axi_rlast_w;
wire         mig_axi_rvalid_w;
wire         mig_axi_rready_w;

assign clk_out_o            = ui_clk_w;
assign ui_rst_w             = ui_clk_sync_rst_w | ~init_calib_complete_w |
                              ~mmcm_locked_w | ~rst_n_i;
assign rst_out_o            = ui_rst_w;
assign init_calib_complete_o = init_calib_complete_w;
assign mmcm_locked_o        = mmcm_locked_w;
assign device_temp_o        = device_temp_w;

// Keep AWCACHE/ARCACHE[1] asserted so the Xilinx width-converter performs
// proper write packing / read serialization on the 32-bit -> 128-bit path.
axi_mem_dwidth
u_axi_mem_dwidth
(
    .s_axi_aclk(ui_clk_w),
    .s_axi_aresetn(~ui_rst_w),
    .s_axi_awid(inport_awid_i),
    .s_axi_awaddr(s_axi_awaddr_w),
    .s_axi_awlen(inport_awlen_i),
    .s_axi_awsize(3'b010),
    .s_axi_awburst(inport_awburst_i),
    .s_axi_awlock(1'b0),
    .s_axi_awcache(4'h2),
    .s_axi_awprot(3'b010),
    .s_axi_awregion(4'b0),
    .s_axi_awqos(4'b0),
    .s_axi_awvalid(inport_awvalid_i),
    .s_axi_awready(inport_awready_o),
    .s_axi_wdata(inport_wdata_i),
    .s_axi_wstrb(inport_wstrb_i),
    .s_axi_wlast(inport_wlast_i),
    .s_axi_wvalid(inport_wvalid_i),
    .s_axi_wready(inport_wready_o),
    .s_axi_bid(inport_bid_o),
    .s_axi_bresp(inport_bresp_o),
    .s_axi_bvalid(inport_bvalid_o),
    .s_axi_bready(inport_bready_i),
    .s_axi_arid(inport_arid_i),
    .s_axi_araddr(s_axi_araddr_w),
    .s_axi_arlen(inport_arlen_i),
    .s_axi_arsize(3'b010),
    .s_axi_arburst(inport_arburst_i),
    .s_axi_arlock(1'b0),
    .s_axi_arcache(4'h2),
    .s_axi_arprot(3'b010),
    .s_axi_arregion(4'b0),
    .s_axi_arqos(4'b0),
    .s_axi_arvalid(inport_arvalid_i),
    .s_axi_arready(inport_arready_o),
    .s_axi_rid(inport_rid_o),
    .s_axi_rdata(inport_rdata_o),
    .s_axi_rresp(inport_rresp_o),
    .s_axi_rlast(inport_rlast_o),
    .s_axi_rvalid(inport_rvalid_o),
    .s_axi_rready(inport_rready_i),
    .m_axi_awaddr(mig_axi_awaddr_w),
    .m_axi_awlen(mig_axi_awlen_w),
    .m_axi_awsize(mig_axi_awsize_w),
    .m_axi_awburst(mig_axi_awburst_w),
    .m_axi_awlock(mig_axi_awlock_w),
    .m_axi_awcache(mig_axi_awcache_w),
    .m_axi_awprot(mig_axi_awprot_w),
    .m_axi_awregion(),
    .m_axi_awqos(mig_axi_awqos_w),
    .m_axi_awvalid(mig_axi_awvalid_w),
    .m_axi_awready(mig_axi_awready_w),
    .m_axi_wdata(mig_axi_wdata_w),
    .m_axi_wstrb(mig_axi_wstrb_w),
    .m_axi_wlast(mig_axi_wlast_w),
    .m_axi_wvalid(mig_axi_wvalid_w),
    .m_axi_wready(mig_axi_wready_w),
    .m_axi_bresp(mig_axi_bresp_w),
    .m_axi_bvalid(mig_axi_bvalid_w),
    .m_axi_bready(mig_axi_bready_w),
    .m_axi_araddr(mig_axi_araddr_w),
    .m_axi_arlen(mig_axi_arlen_w),
    .m_axi_arsize(mig_axi_arsize_w),
    .m_axi_arburst(mig_axi_arburst_w),
    .m_axi_arlock(mig_axi_arlock_w),
    .m_axi_arcache(mig_axi_arcache_w),
    .m_axi_arprot(mig_axi_arprot_w),
    .m_axi_arregion(),
    .m_axi_arqos(mig_axi_arqos_w),
    .m_axi_arvalid(mig_axi_arvalid_w),
    .m_axi_arready(mig_axi_arready_w),
    .m_axi_rdata(mig_axi_rdata_w),
    .m_axi_rresp(mig_axi_rresp_w),
    .m_axi_rlast(mig_axi_rlast_w),
    .m_axi_rvalid(mig_axi_rvalid_w),
    .m_axi_rready(mig_axi_rready_w)
);

ddr3_ip
u_ddr3
(
    .ddr3_dq(ddr3_dq_io),
    .ddr3_dqs_n(ddr3_dqs_n_io),
    .ddr3_dqs_p(ddr3_dqs_p_io),
    .ddr3_addr(ddr3_addr_o),
    .ddr3_ba(ddr3_ba_o),
    .ddr3_ras_n(ddr3_ras_n_o),
    .ddr3_cas_n(ddr3_cas_n_o),
    .ddr3_we_n(ddr3_we_n_o),
    .ddr3_reset_n(ddr3_reset_n_o),
    .ddr3_ck_p(ddr3_ck_p_o),
    .ddr3_ck_n(ddr3_ck_n_o),
    .ddr3_cke(ddr3_cke_o),
    .ddr3_dm(ddr3_dm_o),
    .ddr3_odt(ddr3_odt_o),
    .sys_clk_i(clk_200_i),
    .ui_clk(ui_clk_w),
    .ui_clk_sync_rst(ui_clk_sync_rst_w),
    .mmcm_locked(mmcm_locked_w),
    .aresetn(rst_n_i),
    .app_sr_req(1'b0),
    .app_ref_req(1'b0),
    .app_zq_req(1'b0),
    .app_sr_active(),
    .app_ref_ack(),
    .app_zq_ack(),
    .s_axi_awid(4'b0000),
    .s_axi_awaddr(mig_axi_awaddr_w),
    .s_axi_awlen(mig_axi_awlen_w),
    .s_axi_awsize(mig_axi_awsize_w),
    .s_axi_awburst(mig_axi_awburst_w),
    .s_axi_awlock(mig_axi_awlock_w),
    .s_axi_awcache(mig_axi_awcache_w),
    .s_axi_awprot(mig_axi_awprot_w),
    .s_axi_awqos(mig_axi_awqos_w),
    .s_axi_awvalid(mig_axi_awvalid_w),
    .s_axi_awready(mig_axi_awready_w),
    .s_axi_wdata(mig_axi_wdata_w),
    .s_axi_wstrb(mig_axi_wstrb_w),
    .s_axi_wlast(mig_axi_wlast_w),
    .s_axi_wvalid(mig_axi_wvalid_w),
    .s_axi_wready(mig_axi_wready_w),
    .s_axi_bready(mig_axi_bready_w),
    .s_axi_bid(),
    .s_axi_bresp(mig_axi_bresp_w),
    .s_axi_bvalid(mig_axi_bvalid_w),
    .s_axi_arid(4'b0000),
    .s_axi_araddr(mig_axi_araddr_w),
    .s_axi_arlen(mig_axi_arlen_w),
    .s_axi_arsize(mig_axi_arsize_w),
    .s_axi_arburst(mig_axi_arburst_w),
    .s_axi_arlock(mig_axi_arlock_w),
    .s_axi_arcache(mig_axi_arcache_w),
    .s_axi_arprot(mig_axi_arprot_w),
    .s_axi_arqos(mig_axi_arqos_w),
    .s_axi_arvalid(mig_axi_arvalid_w),
    .s_axi_arready(mig_axi_arready_w),
    .s_axi_rready(mig_axi_rready_w),
    .s_axi_rid(),
    .s_axi_rdata(mig_axi_rdata_w),
    .s_axi_rresp(mig_axi_rresp_w),
    .s_axi_rlast(mig_axi_rlast_w),
    .s_axi_rvalid(mig_axi_rvalid_w),
    .init_calib_complete(init_calib_complete_w),
    .device_temp(device_temp_w),
    .sys_rst(rst_n_i)
);

endmodule
