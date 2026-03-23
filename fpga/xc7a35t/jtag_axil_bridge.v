//-----------------------------------------------------------------
// JTAG AXI-Lite bridge with local control/status window
//-----------------------------------------------------------------
module jtag_axil_bridge
#(
    parameter CONTROL_ADDR = 32'hF000_0000,
    parameter STATUS_ADDR  = 32'hF000_0004,
    parameter VERSION_ADDR = 32'hF000_0008,
    parameter CONSOLE_TX_ADDR = 32'hF000_000C,
    parameter CONSOLE_RX_ADDR = 32'hF000_0010,
    parameter CONSOLE_TX_FIFO_DEPTH = 1024,
    parameter VERSION      = 32'h4A54_4731
)
(
    input           clk_i,
    input           rst_i,

    // AXI4-Lite slave (from JTAG AXI + protocol converter)
    input  [31:0]   s_axi_awaddr_i,
    input  [2:0]    s_axi_awprot_i,
    input           s_axi_awvalid_i,
    output          s_axi_awready_o,
    input  [31:0]   s_axi_wdata_i,
    input  [3:0]    s_axi_wstrb_i,
    input           s_axi_wvalid_i,
    output          s_axi_wready_o,
    output [1:0]    s_axi_bresp_o,
    output          s_axi_bvalid_o,
    input           s_axi_bready_i,
    input  [31:0]   s_axi_araddr_i,
    input  [2:0]    s_axi_arprot_i,
    input           s_axi_arvalid_i,
    output          s_axi_arready_o,
    output [31:0]   s_axi_rdata_o,
    output [1:0]    s_axi_rresp_o,
    output          s_axi_rvalid_o,
    input           s_axi_rready_i,

    // Forwarded lightweight debug port into riscv_soc
    output          dbg_awvalid_o,
    output [31:0]   dbg_awaddr_o,
    output          dbg_wvalid_o,
    output [31:0]   dbg_wdata_o,
    output [3:0]    dbg_wstrb_o,
    output          dbg_bready_o,
    output          dbg_arvalid_o,
    output [31:0]   dbg_araddr_o,
    output          dbg_rready_o,
    input           dbg_awready_i,
    input           dbg_wready_i,
    input           dbg_bvalid_i,
    input  [1:0]    dbg_bresp_i,
    input           dbg_arready_i,
    input           dbg_rvalid_i,
    input  [31:0]   dbg_rdata_i,
    input  [1:0]    dbg_rresp_i,

    input           uart_tx_wr_i,
    input  [7:0]    uart_tx_data_i,
    output          uart_rx_valid_o,
    output [7:0]    uart_rx_data_o,
    input           uart_rx_ready_i,
    output reg      cpu_rst_n_sw_o,
    input  [31:0]   status_word_i
);

localparam [1:0] RESP_OKAY = 2'b00;

localparam [2:0] WR_IDLE      = 3'd0;
localparam [2:0] WR_WAIT_W    = 3'd1;
localparam [2:0] WR_SOC_AW    = 3'd2;
localparam [2:0] WR_SOC_W     = 3'd3;
localparam [2:0] WR_SOC_B     = 3'd4;
localparam [2:0] WR_RESP      = 3'd5;

localparam [1:0] RD_IDLE      = 2'd0;
localparam [1:0] RD_SOC_AR    = 2'd1;
localparam [1:0] RD_SOC_R     = 2'd2;
localparam [1:0] RD_RESP      = 2'd3;

function integer clog2;
    input integer value;
    integer i;
begin
    value = value - 1;
    for (i = 0; value > 0; i = i + 1)
        value = value >> 1;

    if (i == 0)
        clog2 = 1;
    else
        clog2 = i;
end
endfunction

function is_local_address;
    input [31:0] addr;
begin
    case (addr)
    CONTROL_ADDR,
    STATUS_ADDR,
    VERSION_ADDR,
    CONSOLE_TX_ADDR,
    CONSOLE_RX_ADDR:
        is_local_address = 1'b1;
    default:
        is_local_address = 1'b0;
    endcase
end
endfunction

localparam integer CONSOLE_TX_FIFO_AW = clog2(CONSOLE_TX_FIFO_DEPTH);

wire unused_awprot_w = |s_axi_awprot_i;
wire unused_arprot_w = |s_axi_arprot_i;

reg [7:0] console_fifo_q[0:CONSOLE_TX_FIFO_DEPTH-1];
reg [CONSOLE_TX_FIFO_AW-1:0] console_wr_ptr_q;
reg [CONSOLE_TX_FIFO_AW-1:0] console_rd_ptr_q;
reg [CONSOLE_TX_FIFO_AW:0]   console_count_q;
reg                          console_overflow_q;
reg                          rx_inject_pending_q;
reg [7:0]                    rx_inject_data_q;
reg                          rx_inject_overflow_q;

reg [2:0]  wr_state_q;
reg [31:0] wr_addr_q;
reg [31:0] wr_data_q;
reg [3:0]  wr_strb_q;
reg        wr_local_q;
reg [1:0]  wr_resp_q;

reg [1:0]  rd_state_q;
reg [31:0] rd_addr_q;
reg [31:0] rd_data_q;
reg [1:0]  rd_resp_q;

wire local_write_accept_w = ((wr_state_q == WR_IDLE) && s_axi_awvalid_i && s_axi_wvalid_i &&
                             is_local_address(s_axi_awaddr_i)) ||
                            ((wr_state_q == WR_WAIT_W) && s_axi_wvalid_i && wr_local_q);
wire [31:0] local_write_addr_w = (wr_state_q == WR_IDLE) ? s_axi_awaddr_i : wr_addr_q;
wire [31:0] local_write_data_w = s_axi_wdata_i;
wire [3:0]  local_write_strb_w = s_axi_wstrb_i;
wire local_read_accept_w = (rd_state_q == RD_IDLE) && s_axi_arvalid_i &&
                           is_local_address(s_axi_araddr_i);
wire console_clear_overflow_w = local_write_accept_w &&
                                (local_write_addr_w == CONSOLE_TX_ADDR) &&
                                local_write_strb_w[3] && local_write_data_w[31];
wire rx_inject_clear_overflow_w = local_write_accept_w &&
                                  (local_write_addr_w == CONSOLE_RX_ADDR) &&
                                  local_write_strb_w[3] && local_write_data_w[31];
wire rx_inject_write_byte_w = local_write_accept_w &&
                              (local_write_addr_w == CONSOLE_RX_ADDR) &&
                              local_write_strb_w[0];
wire console_empty_w = (console_count_q == 0);
wire console_full_w  = (console_count_q == CONSOLE_TX_FIFO_DEPTH);
wire console_pop_w   = local_read_accept_w &&
                       (s_axi_araddr_i == CONSOLE_TX_ADDR) &&
                       !console_empty_w;
wire [7:0] console_head_data_w = console_empty_w ? 8'h00 : console_fifo_q[console_rd_ptr_q];
wire [13:0] console_level_w = console_count_q;

always @ (posedge clk_i)
begin
    if (rst_i)
    begin
        console_wr_ptr_q     <= {CONSOLE_TX_FIFO_AW{1'b0}};
        console_rd_ptr_q     <= {CONSOLE_TX_FIFO_AW{1'b0}};
        console_count_q      <= {(CONSOLE_TX_FIFO_AW + 1){1'b0}};
        console_overflow_q   <= 1'b0;
        rx_inject_pending_q  <= 1'b0;
        rx_inject_data_q     <= 8'h00;
        rx_inject_overflow_q <= 1'b0;
    end
    else
    begin
        if (console_clear_overflow_w)
            console_overflow_q <= 1'b0;
        if (rx_inject_clear_overflow_w)
            rx_inject_overflow_q <= 1'b0;

        case ({uart_tx_wr_i, console_pop_w})
        2'b01:
        begin
            console_rd_ptr_q <= console_rd_ptr_q + 1'b1;
            console_count_q  <= console_count_q - 1'b1;
        end
        2'b10:
        begin
            if (!console_full_w)
            begin
                console_fifo_q[console_wr_ptr_q] <= uart_tx_data_i;
                console_wr_ptr_q <= console_wr_ptr_q + 1'b1;
                console_count_q  <= console_count_q + 1'b1;
            end
            else
                console_overflow_q <= 1'b1;
        end
        2'b11:
        begin
            console_fifo_q[console_wr_ptr_q] <= uart_tx_data_i;
            console_wr_ptr_q <= console_wr_ptr_q + 1'b1;
            console_rd_ptr_q <= console_rd_ptr_q + 1'b1;
        end
        default:
            ;
        endcase

        if (rx_inject_pending_q && uart_rx_ready_i)
            rx_inject_pending_q <= 1'b0;

        if (rx_inject_write_byte_w)
        begin
            if (!rx_inject_pending_q || uart_rx_ready_i)
            begin
                rx_inject_pending_q <= 1'b1;
                rx_inject_data_q    <= local_write_data_w[7:0];
            end
            else
                rx_inject_overflow_q <= 1'b1;
        end
    end
end

always @ (posedge clk_i)
begin
    if (rst_i)
    begin
        wr_state_q     <= WR_IDLE;
        wr_addr_q      <= 32'b0;
        wr_data_q      <= 32'b0;
        wr_strb_q      <= 4'b0;
        wr_local_q     <= 1'b0;
        wr_resp_q      <= RESP_OKAY;
        cpu_rst_n_sw_o <= 1'b0;
    end
    else
    begin
        case (wr_state_q)
        WR_IDLE:
        begin
            if (s_axi_awvalid_i)
            begin
                wr_addr_q  <= s_axi_awaddr_i;
                wr_local_q <= is_local_address(s_axi_awaddr_i);

                if (s_axi_wvalid_i)
                begin
                    wr_data_q <= s_axi_wdata_i;
                    wr_strb_q <= s_axi_wstrb_i;

                    if (is_local_address(s_axi_awaddr_i))
                    begin
                        if ((s_axi_awaddr_i == CONTROL_ADDR) && s_axi_wstrb_i[0])
                            cpu_rst_n_sw_o <= s_axi_wdata_i[0];
                        wr_resp_q  <= RESP_OKAY;
                        wr_state_q <= WR_RESP;
                    end
                    else
                        wr_state_q <= WR_SOC_AW;
                end
                else
                    wr_state_q <= WR_WAIT_W;
            end
        end
        WR_WAIT_W:
        begin
            if (s_axi_wvalid_i)
            begin
                wr_data_q <= s_axi_wdata_i;
                wr_strb_q <= s_axi_wstrb_i;

                if (wr_local_q)
                begin
                    if ((wr_addr_q == CONTROL_ADDR) && s_axi_wstrb_i[0])
                        cpu_rst_n_sw_o <= s_axi_wdata_i[0];
                    wr_resp_q  <= RESP_OKAY;
                    wr_state_q <= WR_RESP;
                end
                else
                    wr_state_q <= WR_SOC_AW;
            end
        end
        WR_SOC_AW:
        begin
            if (dbg_awready_i)
                wr_state_q <= WR_SOC_W;
        end
        WR_SOC_W:
        begin
            if (dbg_wready_i)
                wr_state_q <= WR_SOC_B;
        end
        WR_SOC_B:
        begin
            if (dbg_bvalid_i)
            begin
                wr_resp_q  <= dbg_bresp_i;
                wr_state_q <= WR_RESP;
            end
        end
        WR_RESP:
        begin
            if (s_axi_bready_i)
                wr_state_q <= WR_IDLE;
        end
        default:
            wr_state_q <= WR_IDLE;
        endcase
    end
end

always @ (posedge clk_i)
begin
    if (rst_i)
    begin
        rd_state_q <= RD_IDLE;
        rd_addr_q  <= 32'b0;
        rd_data_q  <= 32'b0;
        rd_resp_q  <= RESP_OKAY;
    end
    else
    begin
        case (rd_state_q)
        RD_IDLE:
        begin
            if (s_axi_arvalid_i)
            begin
                rd_addr_q <= s_axi_araddr_i;

                if (is_local_address(s_axi_araddr_i))
                begin
                    case (s_axi_araddr_i)
                    CONTROL_ADDR:
                        rd_data_q <= {31'b0, cpu_rst_n_sw_o};
                    STATUS_ADDR:
                        rd_data_q <= status_word_i;
                    VERSION_ADDR:
                        rd_data_q <= VERSION;
                    CONSOLE_TX_ADDR:
                        rd_data_q <= {console_overflow_q,
                                      ~console_empty_w,
                                      console_level_w,
                                      8'h00,
                                      console_head_data_w};
                    CONSOLE_RX_ADDR:
                        rd_data_q <= {rx_inject_overflow_q,
                                      rx_inject_pending_q,
                                      uart_rx_ready_i,
                                      21'b0,
                                      rx_inject_data_q};
                    default:
                        rd_data_q <= 32'b0;
                    endcase
                    rd_resp_q  <= RESP_OKAY;
                    rd_state_q <= RD_RESP;
                end
                else
                    rd_state_q <= RD_SOC_AR;
            end
        end
        RD_SOC_AR:
        begin
            if (dbg_arready_i)
                rd_state_q <= RD_SOC_R;
        end
        RD_SOC_R:
        begin
            if (dbg_rvalid_i)
            begin
                rd_data_q  <= dbg_rdata_i;
                rd_resp_q  <= dbg_rresp_i;
                rd_state_q <= RD_RESP;
            end
        end
        RD_RESP:
        begin
            if (s_axi_rready_i)
                rd_state_q <= RD_IDLE;
        end
        default:
            rd_state_q <= RD_IDLE;
        endcase
    end
end

assign s_axi_awready_o = (wr_state_q == WR_IDLE);
assign s_axi_wready_o  = (wr_state_q == WR_IDLE && s_axi_awvalid_i) ||
                         (wr_state_q == WR_WAIT_W);
assign s_axi_bvalid_o  = (wr_state_q == WR_RESP);
assign s_axi_bresp_o   = wr_resp_q;

assign s_axi_arready_o = (rd_state_q == RD_IDLE);
assign s_axi_rvalid_o  = (rd_state_q == RD_RESP);
assign s_axi_rdata_o   = rd_data_q;
assign s_axi_rresp_o   = rd_resp_q;

assign dbg_awvalid_o = (wr_state_q == WR_SOC_AW);
assign dbg_awaddr_o  = wr_addr_q;
assign dbg_wvalid_o  = (wr_state_q == WR_SOC_W);
assign dbg_wdata_o   = wr_data_q;
assign dbg_wstrb_o   = wr_strb_q;
assign dbg_bready_o  = (wr_state_q == WR_SOC_B);

assign dbg_arvalid_o = (rd_state_q == RD_SOC_AR);
assign dbg_araddr_o  = rd_addr_q;
assign dbg_rready_o  = (rd_state_q == RD_SOC_R);

assign uart_rx_valid_o = rx_inject_pending_q;
assign uart_rx_data_o  = rx_inject_data_q;

endmodule
