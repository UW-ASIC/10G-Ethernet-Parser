`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module gearbox_tx_iso_tb;

    import eth_frame_pkg::*;

    localparam DATA_W  = 64;
    localparam HEAD_W  = 2;
    localparam BLOCK_W = DATA_W + HEAD_W;

    logic                    clk;
    logic                    rst_n;
    logic [HEAD_W - 1 : 0]   i_head;
    logic [DATA_W - 1 : 0]   i_data;
    logic [DATA_W - 1 : 0]   o_data;
    logic                    o_accept;

    gearbox_tx #(.DATA_W(DATA_W), .HEAD_W(HEAD_W)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_head   (i_head),
        .i_data   (i_data),
        .o_data   (o_data),
        .o_accept (o_accept)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n  = 0;
        i_head = '0;
        i_data = '0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    task automatic feed_block(input logic [HEAD_W-1:0] head, input logic [DATA_W-1:0] data);
        while (!o_accept) @(posedge clk);
        i_head = head;
        i_data = data;
        @(posedge clk);
    endtask

    // --------------------------------------------------------------------------
    // isolated test: you're simulating the scrambler upstream (driving 66-bit blocks)
    // and simulating the SerDes downstream (checking 64-bit output words).
    //
    // the fundamental property: 32 input blocks of 66 bits = 2112 bits.
    // 33 output words of 64 bits = 2112 bits. the output bitstream must be
    // identical to the input bitstream, just reframed.
    //
    // *: there's a 1-cycle latency from the output register. account for it.
    //
    // *: the upstream (scrambler/encoder) needs to respect o_accept. when it
    //    drops low, the block on i_head/i_data should be held and not advanced.
    //    simulate this correctly in your feed task.
    // --------------------------------------------------------------------------

    // test 1: reset state
    //   verify o_data = 0 and o_accept = 1 after reset.

    // test 2: backpressure period
    //   o_accept should drop low for exactly 1 cycle every 33 cycles.
    //   run for 4 full periods and verify the timing.

    // test 3: bitstream integrity
    //   feed 32 known blocks, collect 33 output words. concatenate both sides
    //   into a flat bit vector and compare. they should be identical.
    //   *: block format is {data[63:0], head[1:0]}, head in LSBs (transmitted first).
    //      make sure your concatenation order matches the hardware.

    // test 4: multiple periods
    //   run 3+ full periods (96+ blocks) with unique data.
    //   verify bitstream integrity across period boundaries.

    // test 5: mid-stream reset
    //   feed 16 blocks, reset, feed 32 more.
    //   verify the second period works correctly from a clean state.

    // test 6: constant patterns
    //   all-ones and all-zeros. verify output matches (trivial but catches wiring bugs).

    initial begin
        $display("==============================================");
        $display("  gearbox_tx isolated testbench");
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
