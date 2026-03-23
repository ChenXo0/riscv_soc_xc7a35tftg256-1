//-----------------------------------------------------------------
// XC7A35T FTG256 V2 top-level wrapper (DDR3 AXI)
//-----------------------------------------------------------------
module top
(
    input           clk,
    input           rst_n,
    input           uart_rxd,
    output          uart_txd,
    output [3:0]    led,
    inout  [15:0]   ddr3_dq,
    inout  [1:0]    ddr3_dqs_n,
    inout  [1:0]    ddr3_dqs_p,
    output [13:0]   ddr3_addr,
    output [2:0]    ddr3_ba,
    output          ddr3_ras_n,
    output          ddr3_cas_n,
    output          ddr3_we_n,
    output          ddr3_reset_n,
    output [0:0]    ddr3_ck_p,
    output [0:0]    ddr3_ck_n,
    output [0:0]    ddr3_cke,
    output [1:0]    ddr3_dm,
    output [0:0]    ddr3_odt
);

localparam CLK_FREQ_HZ   = 50000000;
localparam MEM_BASE_ADDR = 32'h8000_0000;

wire        axi_awready_w;
wire        axi_wready_w;
wire        axi_bvalid_w;
wire [1:0]  axi_bresp_w;
wire [3:0]  axi_bid_w;
wire        axi_arready_w;
wire        axi_rvalid_w;
wire [31:0] axi_rdata_w;
wire [1:0]  axi_rresp_w;
wire [3:0]  axi_rid_w;
wire        axi_rlast_w;
wire        axi_awvalid_w;
wire [31:0] axi_awaddr_w;
wire [3:0]  axi_awid_w;
wire [7:0]  axi_awlen_w;
wire [1:0]  axi_awburst_w;
wire        axi_wvalid_w;
wire [31:0] axi_wdata_w;
wire [3:0]  axi_wstrb_w;
wire        axi_wlast_w;
wire        axi_bready_w;
wire        axi_arvalid_w;
wire [31:0] axi_araddr_w;
wire [3:0]  axi_arid_w;
wire [7:0]  axi_arlen_w;
wire [1:0]  axi_arburst_w;
wire        axi_rready_w;
wire        ddr_axi_awready_w;
wire        ddr_axi_wready_w;
wire        ddr_axi_bvalid_w;
wire [1:0]  ddr_axi_bresp_w;
wire [3:0]  ddr_axi_bid_w;
wire        ddr_axi_arready_w;
wire        ddr_axi_rvalid_w;
wire [31:0] ddr_axi_rdata_w;
wire [1:0]  ddr_axi_rresp_w;
wire [3:0]  ddr_axi_rid_w;
wire        ddr_axi_rlast_w;
wire        ddr_axi_awvalid_w;
wire [31:0] ddr_axi_awaddr_w;
wire [3:0]  ddr_axi_awid_w;
wire [7:0]  ddr_axi_awlen_w;
wire [1:0]  ddr_axi_awburst_w;
wire        ddr_axi_wvalid_w;
wire [31:0] ddr_axi_wdata_w;
wire [3:0]  ddr_axi_wstrb_w;
wire        ddr_axi_wlast_w;
wire        ddr_axi_bready_w;
wire        ddr_axi_arvalid_w;
wire [31:0] ddr_axi_araddr_w;
wire [3:0]  ddr_axi_arid_w;
wire [7:0]  ddr_axi_arlen_w;
wire [1:0]  ddr_axi_arburst_w;
wire        ddr_axi_rready_w;

wire [31:0] jtag_dbg_awaddr_w;
wire [2:0]  jtag_dbg_awprot_w;
wire        jtag_dbg_awvalid_w;
wire        jtag_dbg_awready_w;
wire [31:0] jtag_dbg_wdata_w;
wire [3:0]  jtag_dbg_wstrb_w;
wire        jtag_dbg_wvalid_w;
wire        jtag_dbg_wready_w;
wire [1:0]  jtag_dbg_bresp_w;
wire        jtag_dbg_bvalid_w;
wire        jtag_dbg_bready_w;
wire [31:0] jtag_dbg_araddr_w;
wire [2:0]  jtag_dbg_arprot_w;
wire        jtag_dbg_arvalid_w;
wire        jtag_dbg_arready_w;
wire [31:0] jtag_dbg_rdata_w;
wire [1:0]  jtag_dbg_rresp_w;
wire        jtag_dbg_rvalid_w;
wire        jtag_dbg_rready_w;
wire        uart_soc_txd_w;
wire [31:0] gpio_output_w;
wire [31:0] gpio_output_enable_w;
wire        rst_cpu_w;
wire [31:0] dbg_status_int_w;
wire [31:0] dbg_cpu_if_pc_w;
wire        dbg_cpu_if_rd_w;
wire [31:0] dbg_cpu_d_addr_w;
wire        dbg_cpu_d_rd_w;
wire [3:0]  dbg_cpu_d_wr_w;

(* keep = "true" *) wire        dbg_clk_w;
(* keep = "true" *) wire [31:0] dbg_status_w;
(* keep = "true" *) wire [31:0] dbg_axi_awaddr_w;
(* keep = "true" *) wire [31:0] dbg_axi_wdata_w;
(* keep = "true" *) wire [31:0] dbg_axi_araddr_w;
(* keep = "true" *) wire [31:0] dbg_axi_rdata_w;
wire [31:0] dbg_cpu_ctrl_w;
(* keep = "true" *) wire [31:0] dbg_ddr_status_w;

wire        clk_200_w;
wire        pll_locked_w;
wire        clk_soc_w;
wire        rst_soc_w;
wire        clk_ddr_ui_w;
wire        rst_ddr_ui_w;
wire        ddr_init_calib_complete_w;
wire        ddr_mmcm_locked_w;
wire [11:0] ddr_device_temp_w;
reg  [1:0]  rst_soc_sync_q;

wire ddr_ref_rst_n_w = rst_n & pll_locked_w;
wire rst_soc_async_w = ~rst_n | ~pll_locked_w;

assign dbg_clk_w        = clk_soc_w;
assign dbg_status_w     = dbg_status_int_w;
assign dbg_axi_awaddr_w = axi_awaddr_w;
assign dbg_axi_wdata_w  = axi_wdata_w;
assign dbg_axi_araddr_w = axi_araddr_w;
assign dbg_axi_rdata_w  = axi_rdata_w;
assign dbg_cpu_ctrl_w   = {26'b0,
                           dbg_cpu_d_wr_w,
                           dbg_cpu_d_rd_w,
                           dbg_cpu_if_rd_w};
assign dbg_ddr_status_w = {14'b0,
                           ddr_device_temp_w,
                           ddr_init_calib_complete_w,
                           ddr_mmcm_locked_w,
                           pll_locked_w,
                           rst_ddr_ui_w,
                           rst_soc_w,
                           rst_cpu_w};

always @ (posedge clk_soc_w or posedge rst_soc_async_w)
if (rst_soc_async_w)
    rst_soc_sync_q <= 2'b11;
else
    rst_soc_sync_q <= {rst_soc_sync_q[0], 1'b0};

assign rst_soc_w = rst_soc_sync_q[1];

BUFG
u_bufg_soc_clk
(
    .I(clk),
    .O(clk_soc_w)
);

pll_ip
u_pll
(
    .clk_in1(clk),
    .clk_out1(clk_200_w),
    .reset(~rst_n),
    .locked(pll_locked_w)
);

xc7a35t_jtag_axi_bd_wrapper
u_jtag_axi
(
    .aclk(clk_soc_w),
    .aresetn(~rst_soc_w),
    .m_axi_awaddr(jtag_dbg_awaddr_w),
    .m_axi_awprot(jtag_dbg_awprot_w),
    .m_axi_awvalid(jtag_dbg_awvalid_w),
    .m_axi_awready(jtag_dbg_awready_w),
    .m_axi_wdata(jtag_dbg_wdata_w),
    .m_axi_wstrb(jtag_dbg_wstrb_w),
    .m_axi_wvalid(jtag_dbg_wvalid_w),
    .m_axi_wready(jtag_dbg_wready_w),
    .m_axi_bresp(jtag_dbg_bresp_w),
    .m_axi_bvalid(jtag_dbg_bvalid_w),
    .m_axi_bready(jtag_dbg_bready_w),
    .m_axi_araddr(jtag_dbg_araddr_w),
    .m_axi_arprot(jtag_dbg_arprot_w),
    .m_axi_arvalid(jtag_dbg_arvalid_w),
    .m_axi_arready(jtag_dbg_arready_w),
    .m_axi_rdata(jtag_dbg_rdata_w),
    .m_axi_rresp(jtag_dbg_rresp_w),
    .m_axi_rvalid(jtag_dbg_rvalid_w),
    .m_axi_rready(jtag_dbg_rready_w)
);

fpga_top
#(
    .CLK_FREQ(CLK_FREQ_HZ),
    .AUTO_BOOT(0)
)
u_top
(
    .clk_i(clk_soc_w),
    .rst_i(rst_soc_w),
    .dbg_awaddr_i(jtag_dbg_awaddr_w),
    .dbg_awprot_i(jtag_dbg_awprot_w),
    .dbg_awvalid_i(jtag_dbg_awvalid_w),
    .dbg_awready_o(jtag_dbg_awready_w),
    .dbg_wdata_i(jtag_dbg_wdata_w),
    .dbg_wstrb_i(jtag_dbg_wstrb_w),
    .dbg_wvalid_i(jtag_dbg_wvalid_w),
    .dbg_wready_o(jtag_dbg_wready_w),
    .dbg_bresp_o(jtag_dbg_bresp_w),
    .dbg_bvalid_o(jtag_dbg_bvalid_w),
    .dbg_bready_i(jtag_dbg_bready_w),
    .dbg_araddr_i(jtag_dbg_araddr_w),
    .dbg_arprot_i(jtag_dbg_arprot_w),
    .dbg_arvalid_i(jtag_dbg_arvalid_w),
    .dbg_arready_o(jtag_dbg_arready_w),
    .dbg_rdata_o(jtag_dbg_rdata_w),
    .dbg_rresp_o(jtag_dbg_rresp_w),
    .dbg_rvalid_o(jtag_dbg_rvalid_w),
    .dbg_rready_i(jtag_dbg_rready_w),

    // AXI memory
    .axi_awready_i(axi_awready_w),
    .axi_wready_i(axi_wready_w),
    .axi_bvalid_i(axi_bvalid_w),
    .axi_bresp_i(axi_bresp_w),
    .axi_bid_i(axi_bid_w),
    .axi_arready_i(axi_arready_w),
    .axi_rvalid_i(axi_rvalid_w),
    .axi_rdata_i(axi_rdata_w),
    .axi_rresp_i(axi_rresp_w),
    .axi_rid_i(axi_rid_w),
    .axi_rlast_i(axi_rlast_w),
    .axi_awvalid_o(axi_awvalid_w),
    .axi_awaddr_o(axi_awaddr_w),
    .axi_awid_o(axi_awid_w),
    .axi_awlen_o(axi_awlen_w),
    .axi_awburst_o(axi_awburst_w),
    .axi_wvalid_o(axi_wvalid_w),
    .axi_wdata_o(axi_wdata_w),
    .axi_wstrb_o(axi_wstrb_w),
    .axi_wlast_o(axi_wlast_w),
    .axi_bready_o(axi_bready_w),
    .axi_arvalid_o(axi_arvalid_w),
    .axi_araddr_o(axi_araddr_w),
    .axi_arid_o(axi_arid_w),
    .axi_arlen_o(axi_arlen_w),
    .axi_arburst_o(axi_arburst_w),
    .axi_rready_o(axi_rready_w),

    // SPI (unused in V1)
    .spi_clk_o(),
    .spi_mosi_o(),
    .spi_cs_o(),
    .spi_miso_i(1'b0),

    // GPIO
    .gpio_output_o(gpio_output_w),
    .gpio_output_enable_o(gpio_output_enable_w),
    .gpio_input_i(32'b0),

    // UART
    .uart_rxd_o(uart_soc_txd_w),
    .uart_txd_i(uart_rxd),

    // Status
    .cpu_rst_o(rst_cpu_w),
    .debug_status_o(dbg_status_int_w),
    .debug_if_pc_o(dbg_cpu_if_pc_w),
    .debug_if_rd_o(dbg_cpu_if_rd_w),
    .debug_d_addr_o(dbg_cpu_d_addr_w),
    .debug_d_rd_o(dbg_cpu_d_rd_w),
    .debug_d_wr_o(dbg_cpu_d_wr_w)
);

axi4_cdc
u_mem_cdc
(
    .wr_clk_i(clk_soc_w),
    .wr_rst_i(rst_soc_w),
    .inport_awvalid_i(axi_awvalid_w),
    .inport_awaddr_i(axi_awaddr_w),
    .inport_awid_i(axi_awid_w),
    .inport_awlen_i(axi_awlen_w),
    .inport_awburst_i(axi_awburst_w),
    .inport_wvalid_i(axi_wvalid_w),
    .inport_wdata_i(axi_wdata_w),
    .inport_wstrb_i(axi_wstrb_w),
    .inport_wlast_i(axi_wlast_w),
    .inport_bready_i(axi_bready_w),
    .inport_arvalid_i(axi_arvalid_w),
    .inport_araddr_i(axi_araddr_w),
    .inport_arid_i(axi_arid_w),
    .inport_arlen_i(axi_arlen_w),
    .inport_arburst_i(axi_arburst_w),
    .inport_rready_i(axi_rready_w),
    .rd_clk_i(clk_ddr_ui_w),
    .rd_rst_i(rst_ddr_ui_w),
    .outport_awready_i(ddr_axi_awready_w),
    .outport_wready_i(ddr_axi_wready_w),
    .outport_bvalid_i(ddr_axi_bvalid_w),
    .outport_bresp_i(ddr_axi_bresp_w),
    .outport_bid_i(ddr_axi_bid_w),
    .outport_arready_i(ddr_axi_arready_w),
    .outport_rvalid_i(ddr_axi_rvalid_w),
    .outport_rdata_i(ddr_axi_rdata_w),
    .outport_rresp_i(ddr_axi_rresp_w),
    .outport_rid_i(ddr_axi_rid_w),
    .outport_rlast_i(ddr_axi_rlast_w),
    .inport_awready_o(axi_awready_w),
    .inport_wready_o(axi_wready_w),
    .inport_bvalid_o(axi_bvalid_w),
    .inport_bresp_o(axi_bresp_w),
    .inport_bid_o(axi_bid_w),
    .inport_arready_o(axi_arready_w),
    .inport_rvalid_o(axi_rvalid_w),
    .inport_rdata_o(axi_rdata_w),
    .inport_rresp_o(axi_rresp_w),
    .inport_rid_o(axi_rid_w),
    .inport_rlast_o(axi_rlast_w),
    .outport_awvalid_o(ddr_axi_awvalid_w),
    .outport_awaddr_o(ddr_axi_awaddr_w),
    .outport_awid_o(ddr_axi_awid_w),
    .outport_awlen_o(ddr_axi_awlen_w),
    .outport_awburst_o(ddr_axi_awburst_w),
    .outport_wvalid_o(ddr_axi_wvalid_w),
    .outport_wdata_o(ddr_axi_wdata_w),
    .outport_wstrb_o(ddr_axi_wstrb_w),
    .outport_wlast_o(ddr_axi_wlast_w),
    .outport_bready_o(ddr_axi_bready_w),
    .outport_arvalid_o(ddr_axi_arvalid_w),
    .outport_araddr_o(ddr_axi_araddr_w),
    .outport_arid_o(ddr_axi_arid_w),
    .outport_arlen_o(ddr_axi_arlen_w),
    .outport_arburst_o(ddr_axi_arburst_w),
    .outport_rready_o(ddr_axi_rready_w)
);

xc7a35t_ddr_axi
#(
    .MEM_BASE_ADDR(MEM_BASE_ADDR)
)
u_ddr
(
    .clk_200_i(clk_200_w),
    .rst_n_i(ddr_ref_rst_n_w),
    .inport_awvalid_i(ddr_axi_awvalid_w),
    .inport_awaddr_i(ddr_axi_awaddr_w),
    .inport_awid_i(ddr_axi_awid_w),
    .inport_awlen_i(ddr_axi_awlen_w),
    .inport_awburst_i(ddr_axi_awburst_w),
    .inport_wvalid_i(ddr_axi_wvalid_w),
    .inport_wdata_i(ddr_axi_wdata_w),
    .inport_wstrb_i(ddr_axi_wstrb_w),
    .inport_wlast_i(ddr_axi_wlast_w),
    .inport_bready_i(ddr_axi_bready_w),    
    .inport_arvalid_i(ddr_axi_arvalid_w),
    .inport_araddr_i(ddr_axi_araddr_w),
    .inport_arid_i(ddr_axi_arid_w),
    .inport_arlen_i(ddr_axi_arlen_w),
    .inport_arburst_i(ddr_axi_arburst_w),
    .inport_rready_i(ddr_axi_rready_w),
    .inport_awready_o(ddr_axi_awready_w),
    .inport_wready_o(ddr_axi_wready_w),
    .inport_bvalid_o(ddr_axi_bvalid_w),
    .inport_bresp_o(ddr_axi_bresp_w),
    .inport_bid_o(ddr_axi_bid_w),
    .inport_arready_o(ddr_axi_arready_w),
    .inport_rvalid_o(ddr_axi_rvalid_w),
    .inport_rdata_o(ddr_axi_rdata_w),
    .inport_rresp_o(ddr_axi_rresp_w),
    .inport_rid_o(ddr_axi_rid_w),
    .inport_rlast_o(ddr_axi_rlast_w),
    .clk_out_o(clk_ddr_ui_w),
    .rst_out_o(rst_ddr_ui_w),
    .init_calib_complete_o(ddr_init_calib_complete_w),
    .mmcm_locked_o(ddr_mmcm_locked_w),
    .device_temp_o(ddr_device_temp_w),
    .ddr3_addr_o(ddr3_addr),
    .ddr3_ba_o(ddr3_ba),
    .ddr3_ras_n_o(ddr3_ras_n),
    .ddr3_cas_n_o(ddr3_cas_n),
    .ddr3_we_n_o(ddr3_we_n),
    .ddr3_reset_n_o(ddr3_reset_n),
    .ddr3_ck_p_o(ddr3_ck_p),
    .ddr3_ck_n_o(ddr3_ck_n),
    .ddr3_cke_o(ddr3_cke),
    .ddr3_dm_o(ddr3_dm),
    .ddr3_odt_o(ddr3_odt),
    .ddr3_dq_io(ddr3_dq),
    .ddr3_dqs_n_io(ddr3_dqs_n),
    .ddr3_dqs_p_io(ddr3_dqs_p)
);

assign uart_txd = uart_soc_txd_w;

wire [3:0] user_led_on_w =
    rst_soc_w ? 4'b0000 : (gpio_output_enable_w[3:0] & gpio_output_w[3:0]);

wire [3:0] led_on_w;
assign led_on_w[0] = (~pll_locked_w)             | user_led_on_w[0];
assign led_on_w[1] = ddr_mmcm_locked_w           | user_led_on_w[1];
assign led_on_w[2] = ddr_init_calib_complete_w   | user_led_on_w[2];
assign led_on_w[3] = (~rst_cpu_w)                | user_led_on_w[3];

// Board LEDs are active-low.
assign led = ~led_on_w;

endmodule
