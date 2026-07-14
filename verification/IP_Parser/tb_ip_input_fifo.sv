`timescale 1ns/1ps
//==========================================
// Testbench for IP Parser Input fifo
//==========================================

module tb_ip_parser_input_fifo ();
    // Parameters and Clock/Reset Generation
    parameter DEPTH = 16; // Smaller than RTL for faster simulation
    parameter ADDRW = $clog2(DEPTH);
    localparam DATAW = 64 + 8 + 1 + 1;

    logic clk, rst_n;

    // 100 MHz Clock generation
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // DUT Interface Signals
    logic [63:0]    s_axis_tdata;
    logic [7:0]     s_axis_tkeep;
    logic           s_axis_tvalid;
    logic           s_axis_tready;
    logic           s_axis_tlast;
    logic [0:0]     s_axis_tuser;

    logic [63:0]    m_axis_tdata;
    logic [7:0]     m_axis_tkeep;
    logic           m_axis_tvalid;
    logic           m_axis_tready;
    logic           m_axis_tlast;
    logic [0:0]     m_axis_tuser;

    // DUT Instantiation
    fifo #(
        .DEPTH(DEPTH),
        .ADDRW(ADDRW)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser)
    );


    // Main Test Flow
    initial begin
        $display("============================================");
        $display("   STARTING FWFT FIFO VERIFICATION          ");
        $display("============================================");

        // ...
    end
endmodule
