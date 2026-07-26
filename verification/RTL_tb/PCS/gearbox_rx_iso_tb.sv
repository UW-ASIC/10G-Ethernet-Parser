`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module gearbox_rx_iso_tb;

    import eth_frame_pkg::*;

    localparam DATA_W  = 64;
    localparam HEAD_W  = 2;
    localparam BLOCK_W = DATA_W + HEAD_W;

    logic                    clk;
    logic                    rst_n;
    logic [DATA_W - 1 : 0]  i_data;
    logic                    i_pma_lock;
    logic                    i_slip;
    logic [BLOCK_W - 1 : 0] o_data;
    logic                    o_valid;
    logic [HEAD_W - 1 : 0]  o_head;

    gearbox_rx #(.DATA_W(DATA_W), .HEAD_W(HEAD_W)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_data     (i_data),
        .i_pma_lock (i_pma_lock),
        .i_slip     (i_slip),
        .o_data     (o_data),
        .o_valid    (o_valid),
        .o_head     (o_head)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n      = 0;
        i_data     = '0;
        i_pma_lock = 0;
        i_slip     = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // --------------------------------------------------------------------------
    // isolated test: you're simulating the SerDes upstream (driving 64-bit words)
    // and simulating block_sync downstream (driving i_slip, checking o_head/o_valid).
    //
    // the key challenge: you need to generate a 64-bit-wide serial stream that
    // contains valid 66-bit blocks at a known alignment. then verify the gearbox
    // extracts them correctly.
    //
    // approach to generate the input stream:
    //   1. create a sequence of 66-bit blocks (e.g. idle blocks with sync = 10)
    //   2. concatenate them into a flat bitstream
    //   3. slice that bitstream into 64-bit words
    //   4. feed those words as i_data, one per cycle
    //
    // *: the block boundaries in the 64-bit stream will NOT be aligned; the gearbox has to find them. if you always start at
    //    offset 0, add a random initial offset to test non-trivial alignment.
    //
    // *: o_valid goes low when the seq counter is 0 or 1 (not enough bits buffered).
    //    this is expected, it's the only module in the PCS that skips cycles.
    //    don't treat it as a bug.
    // --------------------------------------------------------------------------

    // helper: pack a list of 66-bit blocks into 64-bit words with optional bit offset
    //   this simulates what gearbox_tx would produce on the wire.
    //   returns the number of 64-bit words generated.
    //
    //   *: if you want to test alignment search, add a nonzero offset.
    //      offset = 0 means block boundaries are aligned with the stream start.
    //      offset = 17 means the first block starts 17 bits into the first word.
    //      the gearbox should find it either way (after enough slips).

    // test 1: aligned extraction
    //   pack 64 idle blocks at offset 0. feed them. since the alignment is trivial,
    //   the gearbox should extract valid blocks immediately (no slip needed).
    //   verify every extracted block matches the input.

    // test 2: misaligned extraction with slip
    //   pack blocks at a random offset (e.g. 23 bits in).
    //   feed words with pma_lock = 1. check o_head each time o_valid is high.
    //   if the header is invalid (head[0] == head[1]), assert i_slip for 1 cycle.
    //   repeat until you see valid headers consistently.
    //   *: this is you manually doing block_sync's job. how many slips does it take?
    //      worst case should be 65 (try all 66 possible offsets minus 1).

    // test 3: pma_lock gating
    //   hold pma_lock = 0 for 20 cycles while feeding data.
    //   the gearbox should not produce valid output.
    //   assert pma_lock = 1, verify extraction starts.

    // test 4: pma_lock drop and recovery
    //   lock, extract some blocks, drop pma_lock for 10 cycles, reassert.
    //   verify the gearbox re-acquires alignment (may need slips again).

    // test 5: data integrity after lock
    //   once aligned, feed 100+ blocks with known payloads.
    //   compare each extracted block to the expected block.
    //   *: remember to account for any latency in the extraction pipeline.

    // test 6: o_valid pattern
    //   verify o_valid goes low periodically (when seq counter is near 0).
    //   count the ratio of valid to invalid cycles — should be 32 valid per 33 cycles
    //   in steady state (one cycle where the 66-bit window can't be formed).

    initial begin
        $display("==============================================");
        $display("  gearbox_rx isolated testbench");
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
