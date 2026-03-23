//-----------------------------------------------------------------
// Minimal single-clock AXI RAM for XC7A35T V1 bring-up
//-----------------------------------------------------------------
module axi_ram
#(
    parameter MEM_BASE_ADDR  = 32'h8000_0000,
    parameter MEM_SIZE_BYTES = 64 * 1024
)
(
    // Inputs
     input           clk_i
    ,input           rst_i
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
    ,output          inport_awready_o
    ,output          inport_wready_o
    ,output reg      inport_bvalid_o
    ,output reg [1:0] inport_bresp_o
    ,output reg [3:0] inport_bid_o
    ,output          inport_arready_o
    ,output reg      inport_rvalid_o
    ,output reg [31:0] inport_rdata_o
    ,output reg [1:0]  inport_rresp_o
    ,output reg [3:0]  inport_rid_o
    ,output reg        inport_rlast_o
);

//-----------------------------------------------------------------
// Constants / helpers
//-----------------------------------------------------------------
localparam AXI_RESP_OKAY   = 2'b00;
localparam AXI_RESP_DECERR = 2'b11;

localparam integer MEM_WORDS = MEM_SIZE_BYTES / 4;

function integer clog2;
    input integer value;
    integer i;
    begin
        value = value - 1;
        for (i = 0; value > 0; i = i + 1)
            value = value >> 1;
        clog2 = i;
    end
endfunction

localparam integer MEM_ADDR_BITS = clog2(MEM_WORDS);

function [31:0] next_addr;
    input [31:0] addr;
    input [1:0]  burst;
    begin
        case (burst)
        2'b00: next_addr = addr;
        default: next_addr = addr + 32'd4;
        endcase
    end
endfunction

function is_in_range;
    input [31:0] addr;
    begin
        is_in_range = (addr >= MEM_BASE_ADDR) &&
                      (addr < (MEM_BASE_ADDR + MEM_SIZE_BYTES));
    end
endfunction

function [MEM_ADDR_BITS-1:0] addr_to_word;
    input [31:0] addr;
    begin
        addr_to_word = (addr - MEM_BASE_ADDR) >> 2;
    end
endfunction

//-----------------------------------------------------------------
// RAM
//-----------------------------------------------------------------
reg [31:0] ram [0:MEM_WORDS-1];
reg [31:0] ram_rd_data_q;

integer i;
initial
begin
    for (i = 0; i < MEM_WORDS; i = i + 1)
        ram[i] = 32'b0;
`include "sw/uart_hello_mem.vh"
end

//-----------------------------------------------------------------
// Write channel
//-----------------------------------------------------------------
reg        wr_active_q;
reg [31:0] wr_addr_q;
reg [3:0]  wr_id_q;
reg [7:0]  wr_len_q;
reg [1:0]  wr_burst_q;
reg        wr_error_q;

assign inport_awready_o = ~wr_active_q & ~inport_bvalid_o;
assign inport_wready_o  =  wr_active_q & ~inport_bvalid_o;

always @ (posedge clk_i)
begin
    if (rst_i)
    begin
        wr_active_q    <= 1'b0;
        wr_addr_q      <= 32'b0;
        wr_id_q        <= 4'b0;
        wr_len_q       <= 8'b0;
        wr_burst_q     <= 2'b0;
        wr_error_q     <= 1'b0;
        inport_bvalid_o <= 1'b0;
        inport_bresp_o  <= AXI_RESP_OKAY;
        inport_bid_o    <= 4'b0;
    end
    else
    begin
        if (inport_bvalid_o && inport_bready_i)
            inport_bvalid_o <= 1'b0;

        if (~wr_active_q && inport_awvalid_i && inport_awready_o)
        begin
            wr_active_q <= 1'b1;
            wr_addr_q   <= inport_awaddr_i;
            wr_id_q     <= inport_awid_i;
            wr_len_q    <= inport_awlen_i;
            wr_burst_q  <= inport_awburst_i;
            wr_error_q  <= 1'b0;
        end

        if (wr_active_q && inport_wvalid_i && inport_wready_o)
        begin
            if (is_in_range(wr_addr_q))
            begin
                if (inport_wstrb_i[0])
                    ram[addr_to_word(wr_addr_q)][7:0]   <= inport_wdata_i[7:0];
                if (inport_wstrb_i[1])
                    ram[addr_to_word(wr_addr_q)][15:8]  <= inport_wdata_i[15:8];
                if (inport_wstrb_i[2])
                    ram[addr_to_word(wr_addr_q)][23:16] <= inport_wdata_i[23:16];
                if (inport_wstrb_i[3])
                    ram[addr_to_word(wr_addr_q)][31:24] <= inport_wdata_i[31:24];
            end

            if ((wr_len_q == 8'd0) || inport_wlast_i)
            begin
                wr_active_q     <= 1'b0;
                inport_bvalid_o <= 1'b1;
                inport_bid_o    <= wr_id_q;
                inport_bresp_o  <= (wr_error_q || ~is_in_range(wr_addr_q)) ?
                                   AXI_RESP_DECERR : AXI_RESP_OKAY;
            end
            else
            begin
                wr_addr_q  <= next_addr(wr_addr_q, wr_burst_q);
                wr_len_q   <= wr_len_q - 8'd1;
                wr_error_q <= wr_error_q || ~is_in_range(wr_addr_q);
            end
        end
    end
end

//-----------------------------------------------------------------
// Read channel
//-----------------------------------------------------------------
localparam RD_IDLE = 2'd0;
localparam RD_WAIT = 2'd1;
localparam RD_RESP = 2'd2;

reg [1:0]  rd_state_q;
reg [31:0] rd_addr_q;
reg [3:0]  rd_id_q;
reg [7:0]  rd_len_q;
reg [1:0]  rd_burst_q;
reg        rd_error_q;

wire        rd_start_w    = (rd_state_q == RD_IDLE) &&
                            inport_arvalid_i && inport_arready_o;
wire [31:0] rd_next_addr_w = next_addr(rd_addr_q, rd_burst_q);
wire        rd_continue_w = (rd_state_q == RD_RESP) &&
                            inport_rvalid_o && inport_rready_i &&
                            (rd_len_q != 8'd0);
wire        rd_issue_w    = rd_start_w || rd_continue_w;
wire [31:0] rd_issue_addr_w = rd_start_w ? inport_araddr_i : rd_next_addr_w;

assign inport_arready_o = (rd_state_q == RD_IDLE);

always @ (posedge clk_i)
begin
    if (rd_issue_w)
    begin
        if (is_in_range(rd_issue_addr_w))
            ram_rd_data_q <= ram[addr_to_word(rd_issue_addr_w)];
        else
            ram_rd_data_q <= 32'b0;
    end
end

always @ (posedge clk_i)
begin
    if (rst_i)
    begin
        rd_state_q      <= RD_IDLE;
        rd_addr_q       <= 32'b0;
        rd_id_q         <= 4'b0;
        rd_len_q        <= 8'b0;
        rd_burst_q      <= 2'b0;
        rd_error_q      <= 1'b0;
        inport_rvalid_o <= 1'b0;
        inport_rdata_o  <= 32'b0;
        inport_rresp_o  <= AXI_RESP_OKAY;
        inport_rid_o    <= 4'b0;
        inport_rlast_o  <= 1'b0;
    end
    else
    begin
        case (rd_state_q)
        RD_IDLE:
        begin
            if (rd_start_w)
            begin
                rd_addr_q   <= inport_araddr_i;
                rd_id_q     <= inport_arid_i;
                rd_len_q    <= inport_arlen_i;
                rd_burst_q  <= inport_arburst_i;
                rd_error_q  <= ~is_in_range(inport_araddr_i);
                rd_state_q  <= RD_WAIT;
            end
        end
        RD_WAIT:
        begin
            inport_rvalid_o <= 1'b1;
            inport_rdata_o  <= ram_rd_data_q;
            inport_rresp_o  <= rd_error_q ? AXI_RESP_DECERR : AXI_RESP_OKAY;
            inport_rid_o    <= rd_id_q;
            inport_rlast_o  <= (rd_len_q == 8'd0);
            rd_state_q      <= RD_RESP;
        end
        RD_RESP:
        begin
            if (inport_rvalid_o && inport_rready_i)
            begin
                inport_rvalid_o <= 1'b0;

                if (rd_len_q == 8'd0)
                    rd_state_q <= RD_IDLE;
                else
                begin
                    rd_addr_q  <= rd_next_addr_w;
                    rd_len_q   <= rd_len_q - 8'd1;
                    rd_error_q <= ~is_in_range(rd_next_addr_w);
                    rd_state_q <= RD_WAIT;
                end
            end
        end
        default:
            rd_state_q <= RD_IDLE;
        endcase
    end
end

endmodule
