`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module decoder_iso_tb;

    import eth_frame_pkg::*;

    localparam DATA_W = 64;

    logic                      clk;
    logic                      rst_n;
    logic                      i_valid;
    logic [DATA_W + 1 : 0]     i_data;
    logic                      o_valid;
    logic [DATA_W - 1 : 0]     o_data;
    logic [DATA_W/8 - 1 : 0]   o_ctrl;
    logic [DATA_W/8 - 1 : 0]   o_keep;
    logic                      o_start;
    logic                      o_idle;
    logic                      o_terminate;
    logic                      o_error;

    decoder #(.DATA_W(DATA_W)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_valid     (i_valid),
        .i_data      (i_data),
        .o_valid     (o_valid),
        .o_data      (o_data),
        .o_ctrl      (o_ctrl),
        .o_keep      (o_keep),
        .o_start     (o_start),
        .o_idle      (o_idle),
        .o_terminate (o_terminate),
        .o_error     (o_error)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n   = 0;
        i_valid = 0;
        i_data  = '0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // helper: build a 66-bit block in the format the decoder expects
    //   i_data = {payload[63:0], sync_header[1:0]}
    function automatic logic [DATA_W + 1 : 0] make_block(
        input logic [1:0]  sync,
        input logic [63:0] payload
    );
        return {payload, sync};
    endfunction

    // --------------------------------------------------------------------------
    // isolated test: you're simulating the descrambler upstream (driving 66-bit blocks)
    // and simulating the MAC downstream (checking XGMII output).
    //
    // the decoder is purely combinational. output should reflect input same-cycle.
    //
    // you're constructing raw 66-bit blocks by hand; so you need to know
    // the bit layout for each block type from IEEE clause 49 figure 49-7. the block type
    // field sits at i_data[9:2], and the rest of the payload is arranged per type.
    //
    // *: this is where you catch encoding bugs that the encoder might be hiding.
    //    by feeding known bit patterns directly, you isolate decoder behavior from
    //    any encoder issues.
    // --------------------------------------------------------------------------

    // test 1: data block
    //   sync = 01, payload = 8 known bytes. verify o_data matches payload,
    //   o_ctrl = 8'h00, o_keep = 8'hFF, no flags set, no error.

    // test 2: idle block
    //   sync = 10, block type = 0x1E, all control codes = 7'h00 (idle).
    //   verify o_data = 64'h0707070707070707, o_ctrl = 8'hFF, o_idle = 1.

    // test 3: start block (type 0x78)
    //   sync = 10, block type = 0x78, 7 data bytes in the payload.
    //   verify o_data[7:0] = 0xFB (start char), o_data[63:8] = your 7 bytes,
    //   o_ctrl = 8'h01, o_start = 1.

    // test 4: all terminate types
    //   for each TERM_0 through TERM_7: construct the block manually.
    //   verify: correct o_data (data bytes + 0xFD at the right position + idle padding),
    //   correct o_ctrl, correct o_keep, o_terminate = 1.
    //   *: pay close attention to o_keep. TERM_0 should have o_keep = 8'h00,
    //      TERM_7 should have o_keep = 8'h7F. if yours include the terminate
    //      byte in the keep mask, that's a bug.

    // test 5: invalid sync header
    //   sync = 00 and sync = 11.
    //   verify o_error =1 for both.

    // test 6: unrecognized block type
    //   sync = 10, block type = something not in the table (e.g. 0xAB).
    //   verify o_error =1.

    // test 7: bad control code in a valid block type
    //   sync = 10, block type = 0x1E (all control), but put an invalid 7-bit
    //   code in one of the control slots (e.g. 7'h7F).
    //   verify o_error =1 because decode_control_code returns 0xFE.

    // test 8: ordered set blocks
    //   types 0x2D, 0x4B, 0x55, 0x66.
    //   construct with valid O-codes (4'h0 = Q, 4'hF = Fsig).
    //   verify correct o_data placement and o_ctrl flags.
    //   *: also test with an invalid O-code (e.g. 4'h5) —> should trigger o_error.

    initial begin
        $display("==============================================");
        $display("  decoder isolated testbench");
        $display("==============================================");
        pass_count = 0;
        fail_count = 0;

        do_reset();

        // implement tests here

        $display("\n==============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        $finish;
    end

endmodule
