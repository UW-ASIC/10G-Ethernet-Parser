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
        #1;
        rst_n = 1;
    endtask

    task automatic feed_block(input logic [HEAD_W-1:0] head, input logic [DATA_W-1:0] data);
        while (!o_accept) begin
            @(posedge clk);
            #1;
        end
        i_head = head;
        i_data = data;
        @(posedge clk);
        #1;
    endtask

    function automatic logic [BLOCK_W-1:0] make_block(input logic [HEAD_W-1:0] head, input logic [DATA_W-1:0] data);
        return {data, head};
    endfunction

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
        logic [BLOCK_W-1:0] blocks32 [0:31];
        logic [BLOCK_W-1:0] blocks96 [0:95];
        logic [32*BLOCK_W-1:0] stream32;
        logic [96*BLOCK_W-1:0] stream96;
        logic [63:0] expected_word;
        bit test_ok;
        int blk_idx;

        $display("==============================================");
        $display("  gearbox_tx isolated testbench");
        $display("==============================================");
        pass_count = 0;
        fail_count = 0;

        do_reset();

        test_ok = 1;
        if (o_data !== '0 || o_accept !== 1'b1) begin
            $display("  FAIL [test 1]: reset state mismatch");
            test_ok = 0;
        end
        if (test_ok) pass_count++; else fail_count++;

        test_ok = 1;
        i_head = 2'b01;
        i_data = 64'h0123_4567_89ab_cdef;
        for (int cycle = 0; cycle < 132; cycle++) begin
            @(posedge clk);
            #1;
            if (o_accept !== (((cycle + 2) % 33) != 0)) begin
                $display("  FAIL [test 2 cycle %0d]: o_accept=%b", cycle + 1, o_accept);
                test_ok = 0;
            end
        end
        if (test_ok) pass_count++; else fail_count++;

        for (int blk = 0; blk < 32; blk++) begin
            blocks32[blk] = make_block(blk[1:0], 64'h1000_0000_0000_0000 + blk);
            stream32[blk*BLOCK_W +: HEAD_W] = blocks32[blk][1:0];
            stream32[blk*BLOCK_W + HEAD_W +: DATA_W] = blocks32[blk][65:2];
        end

        test_ok = 1;
        blk_idx = 0;
        for (int cycle = 0; cycle < 33; cycle++) begin
            if (o_accept && blk_idx < 32) begin
                i_head = blocks32[blk_idx][1:0];
                i_data = blocks32[blk_idx][65:2];
                blk_idx++;
            end
            @(posedge clk);
            #1;
            expected_word = stream32[cycle*DATA_W +: DATA_W];
            if (!check_match(expected_word, o_data, $sformatf("test 3 word %0d", cycle)))
                test_ok = 0;
        end
        if (test_ok && blk_idx == 32) pass_count++; else fail_count++;

        for (int blk = 0; blk < 96; blk++) begin
            blocks96[blk] = make_block(blk[1:0], 64'h2000_0000_0000_0000 + blk);
            stream96[blk*BLOCK_W +: HEAD_W] = blocks96[blk][1:0];
            stream96[blk*BLOCK_W + HEAD_W +: DATA_W] = blocks96[blk][65:2];
        end

        test_ok = 1;
        blk_idx = 0;
        for (int cycle = 0; cycle < 99; cycle++) begin
            if (o_accept && blk_idx < 96) begin
                i_head = blocks96[blk_idx][1:0];
                i_data = blocks96[blk_idx][65:2];
                blk_idx++;
            end
            @(posedge clk);
            #1;
            expected_word = stream96[cycle*DATA_W +: DATA_W];
            if (!check_match(expected_word, o_data, $sformatf("test 4 word %0d", cycle)))
                test_ok = 0;
        end
        if (test_ok && blk_idx == 96) pass_count++; else fail_count++;

        for (int blk = 0; blk < 16; blk++) begin
            i_head = blk[1:0];
            i_data = 64'h3000_0000_0000_0000 + blk;
            @(posedge clk);
            #1;
        end
        do_reset();

        test_ok = 1;
        if (o_data !== '0 || o_accept !== 1'b1) begin
            $display("  FAIL [test 5 reset]: reset state mismatch");
            test_ok = 0;
        end
        for (int blk = 0; blk < 32; blk++) begin
            blocks32[blk] = make_block(blk[1:0], 64'h4000_0000_0000_0000 + blk);
            stream32[blk*BLOCK_W +: HEAD_W] = blocks32[blk][1:0];
            stream32[blk*BLOCK_W + HEAD_W +: DATA_W] = blocks32[blk][65:2];
        end
        blk_idx = 0;
        for (int cycle = 0; cycle < 33; cycle++) begin
            if (o_accept && blk_idx < 32) begin
                i_head = blocks32[blk_idx][1:0];
                i_data = blocks32[blk_idx][65:2];
                blk_idx++;
            end
            @(posedge clk);
            #1;
            expected_word = stream32[cycle*DATA_W +: DATA_W];
            if (!check_match(expected_word, o_data, $sformatf("test 5 word %0d", cycle)))
                test_ok = 0;
        end
        if (test_ok && blk_idx == 32) pass_count++; else fail_count++;

        test_ok = 1;
        for (int blk = 0; blk < 32; blk++) begin
            blocks32[blk] = make_block(2'b00, '0);
            stream32[blk*BLOCK_W +: HEAD_W] = blocks32[blk][1:0];
            stream32[blk*BLOCK_W + HEAD_W +: DATA_W] = blocks32[blk][65:2];
        end
        blk_idx = 0;
        for (int cycle = 0; cycle < 33; cycle++) begin
            if (o_accept && blk_idx < 32) begin
                i_head = blocks32[blk_idx][1:0];
                i_data = blocks32[blk_idx][65:2];
                blk_idx++;
            end
            @(posedge clk);
            #1;
            expected_word = stream32[cycle*DATA_W +: DATA_W];
            if (!check_match(expected_word, o_data, $sformatf("test 6 zero word %0d", cycle)))
                test_ok = 0;
        end

        do_reset();
        if (o_data !== '0 || o_accept !== 1'b1) begin
            $display("  FAIL [test 6 reset 1]: reset state mismatch");
            test_ok = 0;
        end

        for (int blk = 0; blk < 32; blk++) begin
            blocks32[blk] = make_block(2'b11, 64'hffff_ffff_ffff_ffff);
            stream32[blk*BLOCK_W +: HEAD_W] = blocks32[blk][1:0];
            stream32[blk*BLOCK_W + HEAD_W +: DATA_W] = blocks32[blk][65:2];
        end
        blk_idx = 0;
        for (int cycle = 0; cycle < 33; cycle++) begin
            if (o_accept && blk_idx < 32) begin
                i_head = blocks32[blk_idx][1:0];
                i_data = blocks32[blk_idx][65:2];
                blk_idx++;
            end
            @(posedge clk);
            #1;
            expected_word = stream32[cycle*DATA_W +: DATA_W];
            if (!check_match(expected_word, o_data, $sformatf("test 6 ones word %0d", cycle)))
                test_ok = 0;
        end
        if (test_ok && blk_idx == 32) pass_count++; else fail_count++;

        // implement tests here

        $display("\n==============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        $finish;
    end
endmodule
