`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module encoder_iso_tb;

    import eth_frame_pkg::*;

    localparam DATA_W = 64;

    logic                      clk;
    logic                      rst_n;
    logic                      i_valid;
    logic [DATA_W - 1 : 0]     i_data;
    logic [DATA_W/8 - 1 : 0]   i_ctrl;
    logic [DATA_W/8 - 1 : 0]   i_keep;
    logic                      i_start;
    logic                      i_idle;
    logic                      i_terminate;
    logic                      i_error;
    logic                      o_valid;
    logic [DATA_W + 1 : 0]     o_data;

    encoder #(.DATA_W(DATA_W)) dut (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_valid     (i_valid),
        .i_data      (i_data),
        .i_ctrl      (i_ctrl),
        .i_keep      (i_keep),
        .i_start     (i_start),
        .i_idle      (i_idle),
        .i_terminate (i_terminate),
        .i_error     (i_error),
        .o_valid     (o_valid),
        .o_data      (o_data)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n       = 0;
        i_valid     = 0;
        i_data      = '0;
        i_ctrl      = '0;
        i_keep      = '0;
        i_start     = 0;
        i_idle      = 0;
        i_terminate = 0;
        i_error     = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // --------------------------------------------------------------------------
    // isolated test: you're simulating the MAC TX upstream (driving XGMII beats)
    // and simulating the scrambler downstream (checking the 66-bit encoded output).
    //
    // the encoder is purely combinational. o_data should update same-cycle as inputs.
    //
    // what to check on the output:
    //   - sync header: o_data[1:0] should be 01 for data beats, 10 for control beats
    //   - block type: o_data[9:2] should match the expected type for the input pattern
    //   - payload: remaining 56 bits should contain correctly packed data/control codes
    //
    // *: the encoder is the inverse of the decoder. if you already verified the decoder's
    //    block type table, you know what outputs to expect here. but don't assume the
    //    encoder is correct just because the decoder is, as they were written independently.
    // --------------------------------------------------------------------------

    // test 1: idle encoding
    //   drive: data = 64'h0707070707070707, ctrl = 8'hFF, idle = 1.
    //   expect: sync = 10, block type = 0x1E, payload = 8 x 7'h00 (idle control codes).

    // test 2: start encoding
    //   drive: start beat from build_xgmii_beats (0xFB + 7 data bytes, ctrl = 8'h01).
    //   expect: sync = 10, block type = 0x78, payload = 7 data bytes in correct positions.

    // test 3: data encoding
    //   drive: 8 data bytes, ctrl = 8'h00.
    //   expect: sync = 01, payload = 8 data bytes verbatim.

    // test 4: all terminate positions
    //   for each terminate position (TERM_0 through TERM_7), construct the appropriate
    //   XGMII beat and verify the encoder picks the correct block type code.
    //   *: the encoder determines terminate position from i_keep. verify the mapping:
    //      keep = 8'h00 -> TERM_0 (0x87), keep = 8'h01 -> TERM_1 (0x99), etc.
    //      which way does your encoder compute this? if it uses (i_keep + 1) as a
    //      one-hot, trace through the logic for each value.

    // test 5: full frame sequence
    //   use gen_random_payload() + build_xgmii_beats() to generate a complete beat sequence.
    //   drive every beat through the encoder.
    //   verify: first beat produces block type 0x78, middle beats produce sync=01,
    //   last beat produces the correct TERM_x.

    // test 6: error encoding
    //   drive a beat with i_error = 1.
    //   *: what does the encoder do with this? does it produce a specific block type?
    //      does it set the sync header to 10? check the implementation.

    initial begin
        $display("==============================================");
        $display("  encoder isolated testbench");
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