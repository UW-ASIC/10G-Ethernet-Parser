`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module tx_path_tb;

    import eth_frame_pkg::*;

    localparam DATA_W  = 64;
    localparam HEAD_W  = 2;

    logic clk;
    logic rst_n;

    // MAC TX interface (driven by tb)
    logic                      i_valid;
    logic [DATA_W - 1 : 0]     i_data;
    logic [DATA_W/8 - 1 : 0]   i_ctrl;
    logic [DATA_W/8 - 1 : 0]   i_keep;
    logic                      i_start;
    logic                      i_idle;
    logic                      i_terminate;
    logic                      i_error;

    // SerDes output (checked by tb)
    logic [DATA_W - 1 : 0]     serdes_data;

    // backpressure from gearbox_tx -> encoder (directly wired inside)
    logic                      accept;

    // --------------------------------------------------------------------------
    // full TX path: encoder -> scrambler -> gearbox_tx
    //
    // wire them up in order. the key interconnect signals:
    //   encoder produces:  66-bit block (o_data[65:0]) + o_valid
    //   scrambler consumes: i_enc_data[65:0] + i_valid
    //   scrambler produces: o_scram_data[65:0] + o_valid
    //   gearbox_tx consumes: i_head[1:0] + i_data[63:0]
    //   gearbox_tx produces: o_data[63:0] + o_accept
    //
    // *: gearbox_tx takes head and data as SEPARATE ports. the scrambler
    //    outputs them as a single 66-bit bus. you need to split:
    //      gearbox.i_head = scram.o_scram_data[1:0]
    //      gearbox.i_data = scram.o_scram_data[65:2]
    //
    // *: gearbox_tx's o_accept needs to gate the encoder and scrambler.
    //    when o_accept drops, the encoder should hold its current output.
    //    think about how to wire this, the encoder is combinational, so
    //    it doesn't "hold" anything on its own.  
    //    the MAC side (this tb) needs
    //    to hold its inputs stable when accept is low.
    // --------------------------------------------------------------------------

    // instantiate encoder, scrambler, gearbox_tx here.
    // wire them together as described above.

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

    // helper: drive XGMII beat with backpressure handling
    task automatic drive_beat_bp(input xgmii_beat_t beat);
        while (!accept) @(posedge clk);
        i_valid     = 1;
        i_data      = beat.data;
        i_ctrl      = beat.ctrl;
        i_keep      = beat.keep;
        i_start     = beat.start;
        i_idle      = beat.idle;
        i_terminate = beat.terminate;
        i_error     = 0;
        @(posedge clk);
    endtask

    // --------------------------------------------------------------------------
    // this tb answers the question: does data survive the entire TX pipeline?
    //
    // you can't directly check the SerDes output against XGMII input because
    // it's been encoded, scrambled, and repacked. but you CAN:
    //
    //   1. verify the output bitstream is continuous (no gaps, no X's)
    //   2. verify backpressure propagation (frames stall cleanly when accept drops)
    //   3. feed the output into an RX path (or the rx_path_tb) for full loopback
    //   4. collect the raw output bits and reconstruct blocks manually to verify
    //      encoding and scrambling
    //
    // *: the gearbox has a 1-cycle output latency. the scrambler and encoder are
    //    combinational. total path latency from XGMII input to SerDes output = 1 cycle.
    // --------------------------------------------------------------------------

    // test 1: idle stream
    //   feed 100 idle beats. verify serdes_data has no X's or Z's.
    //   verify backpressure timing (accept drops every 33 cycles).

    // test 2: single frame
    //   generate a frame with build_xgmii_beats. drive it through.
    //   verify no errors, verify accept behavior during the frame.

    // test 3: back-to-back frames with idles
    //   frame, 3 idles, frame, 10 idles, frame.
    //   verify accept drops are handled cleanly between frames.

    // test 4: frame spanning a backpressure event
    //   time a frame so that a data beat coincides with accept going low.
    //   verify the pipeline stalls and resumes correctly.
    //   *: this is the critical test. if the MAC side doesn't hold its inputs
    //      when accept drops, a beat gets lost or duplicated.

    // test 5: sustained load
    //   500+ beats of mixed frames and idles.
    //   collect all serdes_data output words. verify no X/Z values.

    // test 6: mid-stream reset
    //   feed 50 beats, reset, feed 50 more.
    //   verify clean recovery;

    initial begin
        $display("==============================================");
        $display("  TX path integration testbench");
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
