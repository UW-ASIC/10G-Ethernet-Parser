`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module rx_path_tb;

    import eth_frame_pkg::*;

    localparam DATA_W  = 64;
    localparam HEAD_W  = 2;
    localparam BLOCK_W = DATA_W + HEAD_W;

    logic clk;
    logic rst_n;

    // SerDes input (driven by tb)
    logic [DATA_W - 1 : 0]  serdes_data;
    logic                   serdes_valid;

    // MAC RX output (checked by tb)
    logic                      o_valid;
    logic [DATA_W - 1 : 0]     o_data;
    logic [DATA_W/8 - 1 : 0]   o_ctrl;
    logic [DATA_W/8 - 1 : 0]   o_keep;
    logic                      o_start;
    logic                      o_idle;
    logic                      o_terminate;
    logic                      o_error;

    // internal interconnect signals (directly wired)
    logic [BLOCK_W - 1 : 0]   gearbox_block;
    logic                      gearbox_valid;
    logic [HEAD_W - 1 : 0]    gearbox_head;
    logic                      sync_slip;
    logic                      sync_lock;
    logic                      descram_valid;
    logic [DATA_W + 1 : 0]    descram_data;

    // --------------------------------------------------------------------------
    // full RX path: gearbox_rx -> block_sync + descrambler -> decoder
    //
    // interconnect:
    //   gearbox_rx outputs: o_data (66-bit block), o_valid, o_head
    //   block_sync inputs: i_valid (from gearbox), i_head (from gearbox), i_serdes_v
    //   block_sync outputs: o_slip (to gearbox), o_lock
    //   descrambler inputs: i_valid (from gearbox), i_scram_data (from gearbox o_data)
    //   descrambler outputs: o_valid, o_descram_data (66-bit)
    //   decoder inputs: i_valid (from descrambler), i_data (from descrambler)
    //   decoder outputs: all XGMII signals
    //
    // *: block_sync and the descrambler both consume gearbox output.
    //    block_sync only needs the header, descrambler needs the full block.
    //    they run in parallel— block_sync doesn't gate the descrambler.
    //
    // *: should the descrambler be gated by sync_lock? in our design it isn't;
    //    it processes everything the gearbox produces, even before lock.
    //    the decoder will flag errors on misaligned blocks via o_error.
    //    think about whether this is the right choice.
    // --------------------------------------------------------------------------

    // instantiate gearbox_rx, block_sync_rx, descrambler, decoder here.
    // wire them together as described above.

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n        = 0;
        serdes_data  = '0;
        serdes_valid = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // --------------------------------------------------------------------------
    // to test the RX path, you need to generate a realistic SerDes input stream.
    // this means: take 66-bit blocks, SCRAMBLE them (the remote TX does this),
    // then pack them into 64-bit words (as if gearbox_tx did it on the other end).
    //
    // two approaches:
    //   a) instantiate a scrambler + gearbox_tx in the tb to generate the stream.
    //      this is the most realistic but means you're testing with modules that
    //      may have their own bugs.
    //   b) build the stream manually: construct 66-bit blocks, XOR them with a
    //      known LFSR sequence, pack into 64-bit words. more work but fully
    //      controlled.
    //
    // *: approach (a) is recommended for integration testing. if the TX path
    //    works (verified by tx_path_tb), it's a valid stimulus generator.
    //    approach (b) is better for debugging specific RX issues in isolation.
    //
    // for initial bring-up, you can skip scrambling entirely: feed unscrambled
    // blocks. the descrambler will output garbage for the first ~1 block while
    // its LFSR converges, but after that it should recover. this lets you test
    // gearbox + block_sync without worrying about scrambling correctness.
    // --------------------------------------------------------------------------

    // test 1: alignment acquisition
    //   generate a stream of idle blocks (scrambled or not), pack into 64-bit words.
    //   feed into serdes_data with serdes_valid = 1.
    //   monitor sync_lock; it should assert within 66*64 cycles worst case.
    //   *: watch o_error during acquisition, it will fire on misaligned blocks.
    //      that's expected and not a bug.

    // test 2: idle decoding after lock
    //   once locked, verify decoder produces o_idle = 1 with correct data.
    //   if using unscrambled input, there will be ~1 block of garbage after lock
    //   while the descrambler converges. after that, idle beats should be clean.

    // test 3: frame reception
    //   generate a frame: build XGMII beats with build_xgmii_beats(), encode them
    //   (either with the encoder module or by hand), scramble, pack into 64-bit words.
    //   feed through the RX path. verify decoder output matches the original XGMII beats.
    //   *: this is the end-to-end test. if this works, the RX path works.

    // test 4: serdes_valid drop and recovery
    //   lock, stream data, drop serdes_valid for 20 cycles, reassert.
    //   verify block_sync loses lock, then re-acquires it.
    //   verify the decoder doesn't produce valid output during the gap.

    // test 5: sustained traffic
    //   generate 500+ beats of mixed frames and idles.
    //   feed through the full pipeline. count start/terminate events.
    //   verify every frame that went in comes out with matching data.

    // test 6: error injection
    //   corrupt a 64-bit word mid-stream (flip some bits).
    //   verify the decoder flags o_error on the affected block.
    //   verify subsequent blocks still decode correctly (self-synchronizing).

    initial begin
        $display("==============================================");
        $display("  RX path integration testbench");
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
