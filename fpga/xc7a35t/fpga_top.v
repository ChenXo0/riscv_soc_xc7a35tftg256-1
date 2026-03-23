//-----------------------------------------------------------------
// XC7A35T single-clock FPGA top
//-----------------------------------------------------------------
module fpga_top
#(
    parameter CLK_FREQ = 50000000,
    parameter AUTO_BOOT = 0
)
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input  [31:0]   dbg_awaddr_i
    ,input  [2:0]    dbg_awprot_i
    ,input           dbg_awvalid_i
    ,input  [31:0]   dbg_wdata_i
    ,input  [3:0]    dbg_wstrb_i
    ,input           dbg_wvalid_i
    ,input           dbg_bready_i
    ,input  [31:0]   dbg_araddr_i
    ,input  [2:0]    dbg_arprot_i
    ,input           dbg_arvalid_i
    ,input           dbg_rready_i
    ,input           axi_awready_i
    ,input           axi_wready_i
    ,input           axi_bvalid_i
    ,input  [1:0]    axi_bresp_i
    ,input  [3:0]    axi_bid_i
    ,input           axi_arready_i
    ,input           axi_rvalid_i
    ,input  [31:0]   axi_rdata_i
    ,input  [1:0]    axi_rresp_i
    ,input  [3:0]    axi_rid_i
    ,input           axi_rlast_i
    ,input           spi_miso_i
    ,input           uart_txd_i
    ,input  [31:0]   gpio_input_i

    // Outputs
    ,output          dbg_awready_o
    ,output          dbg_wready_o
    ,output [1:0]    dbg_bresp_o
    ,output          dbg_bvalid_o
    ,output          dbg_arready_o
    ,output [31:0]   dbg_rdata_o
    ,output [1:0]    dbg_rresp_o
    ,output          dbg_rvalid_o
    ,output          axi_awvalid_o
    ,output [31:0]   axi_awaddr_o
    ,output [3:0]    axi_awid_o
    ,output [7:0]    axi_awlen_o
    ,output [1:0]    axi_awburst_o
    ,output          axi_wvalid_o
    ,output [31:0]   axi_wdata_o
    ,output [3:0]    axi_wstrb_o
    ,output          axi_wlast_o
    ,output          axi_bready_o
    ,output          axi_arvalid_o
    ,output [31:0]   axi_araddr_o
    ,output [3:0]    axi_arid_o
    ,output [7:0]    axi_arlen_o
    ,output [1:0]    axi_arburst_o
    ,output          axi_rready_o
    ,output          spi_clk_o
    ,output          spi_mosi_o
    ,output          spi_cs_o
    ,output          uart_rxd_o
    ,output [31:0]   gpio_output_o
    ,output [31:0]   gpio_output_enable_o
    ,output          cpu_rst_o
    ,output [31:0]   debug_status_o
    ,output [31:0]   debug_if_pc_o
    ,output          debug_if_rd_o
    ,output [31:0]   debug_d_addr_o
    ,output          debug_d_rd_o
    ,output [3:0]    debug_d_wr_o
);

wire [3:0]  axi_dbg_wstrb_w;
wire        axi_dbg_rready_w;
wire [31:0] axi_dbg_wdata_w;
wire [31:0] axi_dbg_rdata_w;
wire [31:0] axi_dbg_awaddr_w;
wire [1:0]  axi_dbg_bresp_w;
wire        axi_dbg_wvalid_w;
wire [31:0] axi_dbg_araddr_w;
wire [31:0] enable_w;
wire [1:0]  axi_dbg_rresp_w;
wire [31:0] reset_vector_w = 32'h8000_0000;
wire        axi_dbg_rvalid_w;
wire        axi_dbg_awready_w;
wire        axi_dbg_arvalid_w;
wire        axi_dbg_arready_w;
wire        axi_dbg_bvalid_w;
wire        axi_dbg_awvalid_w;
wire        axi_dbg_bready_w;
wire        axi_dbg_wready_w;
wire        rst_cpu_w;
wire        cpu_rst_n_sw_w;
wire [31:0] status_word_w;
wire        debug_uart_tx_wr_w;
wire [7:0]  debug_uart_tx_data_w;
wire        debug_uart_rx_inject_valid_w;
wire [7:0]  debug_uart_rx_inject_data_w;
wire        debug_uart_rx_inject_ready_w;

jtag_axil_bridge u_dbg
(
    .clk_i(clk_i),
    .rst_i(rst_i),
    .s_axi_awaddr_i(dbg_awaddr_i),
    .s_axi_awprot_i(dbg_awprot_i),
    .s_axi_awvalid_i(dbg_awvalid_i),
    .s_axi_awready_o(dbg_awready_o),
    .s_axi_wdata_i(dbg_wdata_i),
    .s_axi_wstrb_i(dbg_wstrb_i),
    .s_axi_wvalid_i(dbg_wvalid_i),
    .s_axi_wready_o(dbg_wready_o),
    .s_axi_bresp_o(dbg_bresp_o),
    .s_axi_bvalid_o(dbg_bvalid_o),
    .s_axi_bready_i(dbg_bready_i),
    .s_axi_araddr_i(dbg_araddr_i),
    .s_axi_arprot_i(dbg_arprot_i),
    .s_axi_arvalid_i(dbg_arvalid_i),
    .s_axi_arready_o(dbg_arready_o),
    .s_axi_rdata_o(dbg_rdata_o),
    .s_axi_rresp_o(dbg_rresp_o),
    .s_axi_rvalid_o(dbg_rvalid_o),
    .s_axi_rready_i(dbg_rready_i),

    .dbg_awvalid_o(axi_dbg_awvalid_w),
    .dbg_awaddr_o(axi_dbg_awaddr_w),
    .dbg_wvalid_o(axi_dbg_wvalid_w),
    .dbg_wdata_o(axi_dbg_wdata_w),
    .dbg_wstrb_o(axi_dbg_wstrb_w),
    .dbg_bready_o(axi_dbg_bready_w),
    .dbg_arvalid_o(axi_dbg_arvalid_w),
    .dbg_araddr_o(axi_dbg_araddr_w),
    .dbg_rready_o(axi_dbg_rready_w),
    .dbg_awready_i(axi_dbg_awready_w),
    .dbg_wready_i(axi_dbg_wready_w),
    .dbg_bvalid_i(axi_dbg_bvalid_w),
    .dbg_bresp_i(axi_dbg_bresp_w),
    .dbg_arready_i(axi_dbg_arready_w),
    .dbg_rvalid_i(axi_dbg_rvalid_w),
    .dbg_rdata_i(axi_dbg_rdata_w),
    .dbg_rresp_i(axi_dbg_rresp_w),

    .uart_tx_wr_i(debug_uart_tx_wr_w),
    .uart_tx_data_i(debug_uart_tx_data_w),
    .uart_rx_valid_o(debug_uart_rx_inject_valid_w),
    .uart_rx_data_o(debug_uart_rx_inject_data_w),
    .uart_rx_ready_i(debug_uart_rx_inject_ready_w),
    .cpu_rst_n_sw_o(cpu_rst_n_sw_w),
    .status_word_i(status_word_w)
);

riscv_soc u_soc
(
    // Inputs
     .clk_i(clk_i)
    ,.rst_i(rst_i)
    ,.reset_vector_i(reset_vector_w)
    ,.inport_awvalid_i(axi_dbg_awvalid_w)
    ,.inport_awaddr_i(axi_dbg_awaddr_w)
    ,.inport_wvalid_i(axi_dbg_wvalid_w)
    ,.inport_wdata_i(axi_dbg_wdata_w)
    ,.inport_wstrb_i(axi_dbg_wstrb_w)
    ,.inport_bready_i(axi_dbg_bready_w)
    ,.inport_arvalid_i(axi_dbg_arvalid_w)
    ,.inport_araddr_i(axi_dbg_araddr_w)
    ,.inport_rready_i(axi_dbg_rready_w)
    ,.rst_cpu_i(rst_cpu_w)
    ,.spi_miso_i(spi_miso_i)
    ,.uart_txd_i(uart_txd_i)
    ,.debug_uart_rx_inject_valid_i(debug_uart_rx_inject_valid_w)
    ,.debug_uart_rx_inject_data_i(debug_uart_rx_inject_data_w)
    ,.gpio_input_i(gpio_input_i)
    ,.mem_awready_i(axi_awready_i)
    ,.mem_wready_i(axi_wready_i)
    ,.mem_bvalid_i(axi_bvalid_i)
    ,.mem_bresp_i(axi_bresp_i)
    ,.mem_bid_i(axi_bid_i)
    ,.mem_arready_i(axi_arready_i)
    ,.mem_rvalid_i(axi_rvalid_i)
    ,.mem_rdata_i(axi_rdata_i)
    ,.mem_rresp_i(axi_rresp_i)
    ,.mem_rid_i(axi_rid_i)
    ,.mem_rlast_i(axi_rlast_i)

    // Outputs
    ,.inport_awready_o(axi_dbg_awready_w)
    ,.inport_wready_o(axi_dbg_wready_w)
    ,.inport_bvalid_o(axi_dbg_bvalid_w)
    ,.inport_bresp_o(axi_dbg_bresp_w)
    ,.inport_arready_o(axi_dbg_arready_w)
    ,.inport_rvalid_o(axi_dbg_rvalid_w)
    ,.inport_rdata_o(axi_dbg_rdata_w)
    ,.inport_rresp_o(axi_dbg_rresp_w)
    ,.spi_clk_o(spi_clk_o)
    ,.spi_mosi_o(spi_mosi_o)
    ,.spi_cs_o(spi_cs_o)
    ,.uart_rxd_o(uart_rxd_o)
    ,.debug_uart_tx_wr_o(debug_uart_tx_wr_w)
    ,.debug_uart_tx_data_o(debug_uart_tx_data_w)
    ,.debug_uart_rx_inject_ready_o(debug_uart_rx_inject_ready_w)
    ,.gpio_output_o(gpio_output_o)
    ,.gpio_output_enable_o(gpio_output_enable_o)
    ,.mem_awvalid_o(axi_awvalid_o)
    ,.mem_awaddr_o(axi_awaddr_o)
    ,.mem_awid_o(axi_awid_o)
    ,.mem_awlen_o(axi_awlen_o)
    ,.mem_awburst_o(axi_awburst_o)
    ,.mem_wvalid_o(axi_wvalid_o)
    ,.mem_wdata_o(axi_wdata_o)
    ,.mem_wstrb_o(axi_wstrb_o)
    ,.mem_wlast_o(axi_wlast_o)
    ,.mem_bready_o(axi_bready_o)
    ,.mem_arvalid_o(axi_arvalid_o)
    ,.mem_araddr_o(axi_araddr_o)
    ,.mem_arid_o(axi_arid_o)
    ,.mem_arlen_o(axi_arlen_o)
    ,.mem_arburst_o(axi_arburst_o)
    ,.mem_rready_o(axi_rready_o)
    ,.debug_if_pc_o(debug_if_pc_o)
    ,.debug_if_rd_o(debug_if_rd_o)
    ,.debug_d_addr_o(debug_d_addr_o)
    ,.debug_d_rd_o(debug_d_rd_o)
    ,.debug_d_wr_o(debug_d_wr_o)
);

//-------------------------------------------------------------
// Debug
//-------------------------------------------------------------
assign rst_cpu_w     = AUTO_BOOT ? rst_i : (rst_i | ~cpu_rst_n_sw_w);
assign cpu_rst_o = rst_cpu_w;
assign status_word_w = {12'b0,
                        axi_bready_o,
                        axi_bvalid_i,
                        axi_wready_i,
                        axi_wvalid_o,
                        axi_awready_i,
                        axi_awvalid_o,
                        axi_rready_o,
                        axi_rvalid_i,
                        axi_arready_i,
                        axi_arvalid_o,
                        gpio_output_o[3:0],
                        gpio_output_enable_o[3:0],
                        rst_cpu_w,
                        rst_i};
assign debug_status_o = status_word_w;

endmodule
