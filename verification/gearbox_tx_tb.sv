`timescale 1ns / 1ps

module gearbox_tx_tb;

    localparam DATA_W  = 64;
    localparam HEAD_W  = 2;
    localparam BLOCK_W = DATA_W + HEAD_W;

    logic                    clk;
    logic                    rst_n;
    logic [HEAD_W - 1 : 0]   i_head;
    logic [DATA_W - 1 : 0]   i_data;
    logic [DATA_W - 1 : 0]   o_data;
    logic                    o_accept;

    gearbox_tx #(
        .DATA_W(DATA_W),
        .HEAD_W(HEAD_W)
    ) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_head   (i_head),
        .i_data   (i_data),
        .o_data   (o_data),
        .o_accept (o_accept)
    );

    // 156.25 MHz clock (6.4 ns period)
    initial clk = 0;
    always #3.2 clk = ~clk;

    // ----------------------------------------------------------------
    // golden model: collect all bits fed in, collect all bits coming out,
    // compare that the output bitstream matches the input bitstream.
    // ----------------------------------------------------------------
    // input side: every cycle that o_accept is high, we feed a 66-bit block.
    // output side: every cycle after reset, we get 64 bits out (1 cycle latency from output register).

    localparam MAX_BLOCKS = 256;
    logic [BLOCK_W - 1 : 0] fed_blocks [0 : MAX_BLOCKS - 1];
    int fed_count;

    int pass_count;
    int fail_count;

    // task: apply reset
    task automatic do_reset();
        rst_n  = 0;
        i_head = '0;
        i_data = '0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // task: feed one block (respects o_accept)
    task automatic feed_block(input logic [HEAD_W-1:0] head, input logic [DATA_W-1:0] data);
        // wait until o_accept is high
        while (!o_accept) @(posedge clk);
        i_head = head;
        i_data = data;
        @(posedge clk);
    endtask

    // ================================================================
    // test 1: reset clears outputs
    // ================================================================
    task automatic test_reset();
        $display("\n[TEST 1] Reset clears outputs");
        do_reset();
        // after reset, o_data should be 0 (output register cleared)
        // check on the next clock edge
        @(negedge clk);
        if (o_data !== '0) begin
            $display("  FAIL: o_data = %h after reset, expected 0", o_data);
            fail_count++;
        end else begin
            $display("  PASS: o_data is 0 after reset");
            pass_count++;
        end
        if (o_accept !== 1'b1) begin
            $display("  FAIL: o_accept = %b after reset, expected 1", o_accept);
            fail_count++;
        end else begin
            $display("  PASS: o_accept is 1 after reset");
            pass_count++;
        end
    endtask

    // ================================================================
    // test 2: sequence counter cycles 0-32, o_accept deasserts at seq=32
    // ================================================================
    task automatic test_seq_counter_and_accept();
        $display("\n[TEST 2] Sequence counter cycling and o_accept backpressure");
        do_reset();

        // feed 32 blocks (seq goes 0..31), then on cycle 33 seq=32 and o_accept drops
        for (int i = 0; i < 32; i++) begin
            if (!o_accept) begin
                $display("  FAIL: o_accept dropped early at block %0d", i);
                fail_count++;
                return;
            end
            i_head = 2'b01;
            i_data = i[DATA_W-1:0];
            @(posedge clk);
        end

        // now seq should be 32, o_accept should be low
        @(negedge clk);
        if (o_accept !== 1'b0) begin
            $display("  FAIL: o_accept = %b at seq=32, expected 0", o_accept);
            fail_count++;
        end else begin
            $display("  PASS: o_accept deasserts at seq=32");
            pass_count++;
        end

        // next cycle seq resets to 0, o_accept should go back high
        @(posedge clk);
        @(negedge clk);
        if (o_accept !== 1'b1) begin
            $display("  FAIL: o_accept = %b after seq reset, expected 1", o_accept);
            fail_count++;
        end else begin
            $display("  PASS: o_accept reasserts after seq reset");
            pass_count++;
        end
    endtask

    // ================================================================
    // test 3: bit-level reconstruction over one full 33-cycle period
    // ================================================================
    // feed 32 known blocks, collect 33 output words, concatenate output
    // bits and verify they match the concatenated input bits.
    task automatic test_bitstream_integrity();
        // generate 32 deterministic blocks
        logic [BLOCK_W-1:0] blocks [0:31];
        // total input bits: 32 * 66 = 2112
        // total output bits: 33 * 64 = 2112
        logic [2111:0] input_stream;
        logic [2111:0] output_stream;
        logic [DATA_W-1:0] captured [0:32];
        int feed_idx;
        int capture_idx;

        $display("\n[TEST 3] Bitstream integrity over one full period (32 blocks -> 33 words)");
        do_reset();

        for (int i = 0; i < 32; i++) begin
            blocks[i] = {6'(i[5:0] * 7 + 3), 58'(i * 64'hDEAD_BEEF_CAFE_0001 + 1), i[1:0] ^ 2'b01};
        end

        // build expected input bitstream (block 0 in LSBs, block 31 in MSBs)
        for (int i = 0; i < 32; i++) begin
            input_stream[i*66 +: 66] = blocks[i];
        end

        // feed blocks and collect outputs using a unified pipeline loop
        feed_idx = 0;
        capture_idx = 0;
        while (capture_idx < 33) begin
            if (feed_idx < 32 && o_accept) begin
                i_head = blocks[feed_idx][1:0];
                i_data = blocks[feed_idx][65:2];
            end else begin
                i_head = '0;
                i_data = '0;
            end

            @(posedge clk);
            @(negedge clk);
            captured[capture_idx] = o_data;
            capture_idx++;

            if (feed_idx < 32 && o_accept) begin
                feed_idx++;
            end
        end

        // build output bitstream
        for (int i = 0; i < 33; i++) begin
            output_stream[i*64 +: 64] = captured[i];
        end

        if (input_stream === output_stream) begin
            $display("  PASS: output bitstream matches input bitstream (2112 bits)");
            pass_count++;
        end else begin
            $display("  FAIL: bitstream mismatch");
            // find first mismatching bit
            for (int b = 0; b < 2112; b++) begin
                if (input_stream[b] !== output_stream[b]) begin
                    $display("  First mismatch at bit %0d: expected %b, got %b", b, input_stream[b], output_stream[b]);
                    break;
                end
            end
            fail_count++;
        end
    endtask

    // ================================================================
    // test 4: known pattern — all-ones blocks
    // ================================================================
    task automatic test_all_ones();
        logic all_ok;
        $display("\n[TEST 4] All-ones blocks produce all-ones output");
        do_reset();

        // feed 33 cycles of all-ones (32 blocks + 1 flush)
        // when every input bit is 1, every output bit should be 1 (after pipeline fills)
        for (int i = 0; i < 32; i++) begin
            while (!o_accept) @(posedge clk);
            i_head = 2'b11;
            i_data = {DATA_W{1'b1}};
            @(posedge clk);
        end

        // wait for flush cycle + output register latency
        @(posedge clk);
        @(posedge clk);
        @(negedge clk);

        // by now the pipeline is full of ones; check a few outputs
        // (skip first output which may contain reset-to-ones transition)
        all_ok = 1;
        for (int i = 0; i < 5; i++) begin
            // keep feeding ones
            while (!o_accept) @(posedge clk);
            i_head = 2'b11;
            i_data = {DATA_W{1'b1}};
            @(posedge clk);
            @(negedge clk);
            if (o_data !== {DATA_W{1'b1}}) begin
                $display("  FAIL: o_data = %h, expected all ones at steady-state cycle %0d", o_data, i);
                all_ok = 0;
            end
        end
        if (all_ok) begin
            $display("  PASS: steady-state all-ones output verified");
            pass_count++;
        end else begin
            fail_count++;
        end
    endtask

    // ================================================================
    // test 5: known pattern — all-zeros blocks
    // ================================================================
    task automatic test_all_zeros();
        logic all_ok;
        $display("\n[TEST 5] All-zeros blocks produce all-zeros output");
        do_reset();

        for (int i = 0; i < 32; i++) begin
            while (!o_accept) @(posedge clk);
            i_head = 2'b00;
            i_data = '0;
            @(posedge clk);
        end

        @(posedge clk);
        @(posedge clk);
        @(negedge clk);

        all_ok = 1;
        for (int i = 0; i < 5; i++) begin
            while (!o_accept) @(posedge clk);
            i_head = 2'b00;
            i_data = '0;
            @(posedge clk);
            @(negedge clk);
            if (o_data !== '0) begin
                $display("  FAIL: o_data = %h, expected all zeros at steady-state cycle %0d", o_data, i);
                all_ok = 0;
            end
        end
        if (all_ok) begin
            $display("  PASS: steady-state all-zeros output verified");
            pass_count++;
        end else begin
            fail_count++;
        end
    endtask

    // ================================================================
    // test 6: o_accept timing — exactly 1 cycle low every 33 cycles
    // ================================================================
    task automatic test_accept_period();
        int cycle_count;
        int deassert_count;
        int last_deassert;
        int gaps [0:3];
        int gap_idx;
        logic gaps_ok;

        $display("\n[TEST 6] o_accept deasserts for exactly 1 cycle every 33 cycles");
        do_reset();

        cycle_count    = 0;
        deassert_count = 0;
        last_deassert  = -1;
        gap_idx        = 0;

        // run for 4 full periods (4 * 33 = 132 cycles)
        for (int c = 0; c < 132; c++) begin
            if (o_accept) begin
                i_head = 2'b01;
                i_data = c[DATA_W-1:0];
            end
            @(posedge clk);
            @(negedge clk);
            if (!o_accept) begin
                if (last_deassert >= 0 && gap_idx < 4) begin
                    gaps[gap_idx] = c - last_deassert;
                    gap_idx++;
                end
                last_deassert = c;
                deassert_count++;
            end
            cycle_count++;
        end

        if (deassert_count == 4) begin
            $display("  PASS: o_accept deasserted exactly 4 times in 132 cycles");
            pass_count++;
        end else begin
            $display("  FAIL: o_accept deasserted %0d times, expected 4", deassert_count);
            fail_count++;
        end

        // check gap between deassertions is 33
        gaps_ok = 1;
        for (int g = 0; g < gap_idx; g++) begin
            if (gaps[g] != 33) begin
                $display("  FAIL: gap[%0d] = %0d, expected 33", g, gaps[g]);
                gaps_ok = 0;
            end
        end
        if (gaps_ok && gap_idx > 0) begin
            $display("  PASS: all gaps between deassertions are 33 cycles");
            pass_count++;
        end else if (!gaps_ok) begin
            fail_count++;
        end
    endtask

    // ================================================================
    // test 7: multi-period sustained streaming with unique blocks
    // ================================================================
    task automatic test_sustained_streaming();
        int blocks_fed;
        int outputs_collected;

        $display("\n[TEST 7] Sustained streaming over 3 full periods (96 blocks)");
        do_reset();

        blocks_fed = 0;
        outputs_collected = 0;

        // run for enough cycles to feed 96 blocks
        // 96 blocks need 96 + 3 flush cycles = 99 active cycles, plus output latency
        for (int c = 0; c < 110; c++) begin
            @(negedge clk);
            if (c > 0) outputs_collected++;

            @(posedge clk);
            if (o_accept && blocks_fed < 96) begin
                i_head = blocks_fed[1:0];
                i_data = 64'hA5A5_0000_0000_0000 | blocks_fed[DATA_W-1:0];
                blocks_fed++;
            end else begin
                i_head = '0;
                i_data = '0;
            end
        end

        $display("  Blocks fed: %0d, Output words collected: %0d", blocks_fed, outputs_collected);
        if (blocks_fed == 96) begin
            $display("  PASS: all 96 blocks fed successfully with backpressure handling");
            pass_count++;
        end else begin
            $display("  FAIL: only %0d blocks fed", blocks_fed);
            fail_count++;
        end
    endtask

    // ================================================================
    // main
    // ================================================================
    initial begin
        $display("==============================================");
        $display("  gearbox_tx testbench");
        $display("==============================================");

        pass_count = 0;
        fail_count = 0;

        test_reset();
        test_seq_counter_and_accept();
        test_bitstream_integrity();
        test_all_ones();
        test_all_zeros();
        test_accept_period();
        test_sustained_streaming();

        $display("\n==============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");

        if (fail_count > 0)
            $display("  *** SOME TESTS FAILED ***");
        else
            $display("  *** ALL TESTS PASSED ***");

        $finish;
    end

endmodule
