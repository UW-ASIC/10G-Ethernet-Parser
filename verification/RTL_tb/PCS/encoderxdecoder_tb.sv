`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module encoderxdecoder_tb;

    import eth_frame_pkg::*;

    localparam DATA_W = 64;

    logic clk;
    logic rst_n;

    // encoder input (driven by tb — simulates MAC TX)
    logic                      enc_i_valid;
    logic [DATA_W - 1 : 0]     enc_i_data;
    logic [DATA_W/8 - 1 : 0]   enc_i_ctrl;
    logic [DATA_W/8 - 1 : 0]   enc_i_keep;
    logic                      enc_i_start;
    logic                      enc_i_idle;
    logic                      enc_i_terminate;
    logic                      enc_i_error;

    // encoder -> decoder interconnect
    logic                      enc_o_valid;
    logic [DATA_W + 1 : 0]     enc_o_data;

    // decoder output (checked by tb)
    logic                      dec_o_valid;
    logic [DATA_W - 1 : 0]     dec_o_data;
    logic [DATA_W/8 - 1 : 0]   dec_o_ctrl;
    logic [DATA_W/8 - 1 : 0]   dec_o_keep;
    logic                      dec_o_start;
    logic                      dec_o_idle;
    logic                      dec_o_terminate;
    logic                      dec_o_error;

    encoder #(.DATA_W(DATA_W)) u_enc (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_valid     (enc_i_valid),
        .i_data      (enc_i_data),
        .i_ctrl      (enc_i_ctrl),
        .i_keep      (enc_i_keep),
        .i_start     (enc_i_start),
        .i_idle      (enc_i_idle),
        .i_terminate (enc_i_terminate),
        .i_error     (enc_i_error),
        .o_valid     (enc_o_valid),
        .o_data      (enc_o_data)
    );

    decoder #(.DATA_W(DATA_W)) u_dec (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_valid     (enc_o_valid),
        .i_data      (enc_o_data),
        .o_valid     (dec_o_valid),
        .o_data      (dec_o_data),
        .o_ctrl      (dec_o_ctrl),
        .o_keep      (dec_o_keep),
        .o_start     (dec_o_start),
        .o_idle      (dec_o_idle),
        .o_terminate (dec_o_terminate),
        .o_error     (dec_o_error)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n = 0;
        enc_i_valid     = 0;
        enc_i_data      = '0;
        enc_i_ctrl      = '0;
        enc_i_keep      = '0;
        enc_i_start     = 0;
        enc_i_idle      = 0;
        enc_i_terminate = 0;
        enc_i_error     = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // helper: drive one XGMII beat into the encoder
    task automatic drive_beat(input xgmii_beat_t beat);
        enc_i_valid     = 1;
        enc_i_data      = beat.data;
        enc_i_ctrl      = beat.ctrl;
        enc_i_keep      = beat.keep;
        enc_i_start     = beat.start;
        enc_i_idle      = beat.idle;
        enc_i_terminate = beat.terminate;
        enc_i_error     = 0;
        @(posedge clk);
    endtask

    // --------------------------------------------------------------------------
    // the core invariant: XGMII beats fed into the encoder should come out
    // of the decoder with identical data/ctrl/keep/start/terminate/idle flags.
    //
    // both encoder and decoder are combinational (zero latency). so the
    // round-trip result should be available on the same cycle.
    //
    // *: think carefully about what "identical" means for o_keep on terminate
    //    blocks. does the encoder preserve the exact keep value, or does it
    //    reconstruct it from the block type on decode? are there cases where
    //    the encoder's encoding of keep loses information that the decoder
    //    can't recover? (hint: it shouldn't, but verify.)
    //
    // *: o_error should never assert on valid round-trip data. if it does,
    //    either the encoder is producing malformed blocks or the decoder is
    //    rejecting valid ones. either way, that's a bug; figure out which side.
    // --------------------------------------------------------------------------

    // test 1: idle round-trip
    //   drive 10 idle beats (data = 64'h0707070707070707, ctrl = 8'hFF, idle = 1).
    //   decoder output should have o_idle = 1, o_error = 0, matching data.

    // test 2: single frame round-trip
    //   use gen_random_payload() + build_xgmii_beats() to generate a beat sequence.
    //   drive start beat, data beats, terminate beat.
    //   check every output beat matches the input beat.
    //   *: pay attention to the terminate beat

    // test 3: all 8 terminate positions
    //   generate frames with payload lengths that produce terminate at each
    //   possible byte position (0 through 7). verify o_keep and o_terminate
    //   are correct for each.
    //   *: use gen_random_payload with specific len values to hit each position.
    //      which payload lengths hit which TERM_x block type?

    // test 4: back-to-back frames
    //   frame1 terminate beat immediately followed by frame2 start beat.
    //   verify clean transition, no lingering flags from the previous frame.

    // test 5: interleaved idles and frames
    //   frame, 5 idles, frame, 1 idle, frame, 20 idles.
    //   verify idle detection and frame boundaries are clean throughout.

    // test 6: error injection
    //   drive a beat with i_error = 1.
    //   verify the encoder produces an error block and the decoder flags o_error.
    //   *: what block type does the encoder use for errors? does the decoder
    //      handle it the same way as an unrecognized block type?

    initial begin
        $display("==============================================");
        $display("  encoder x decoder testbench");
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