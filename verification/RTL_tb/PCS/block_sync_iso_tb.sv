`timescale 1ns / 1ps

module block_sync_iso_tb;

    localparam HEAD_W = 2;

    logic                    clk;
    logic                    rst_n;
    logic                    i_serdes_v;
    logic                    i_valid;
    logic [HEAD_W - 1 : 0]  i_head;
    logic                    o_slip;
    logic                    o_lock;

    block_sync_rx #(.HEAD_W(HEAD_W)) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_serdes_v (i_serdes_v),
        .i_valid    (i_valid),
        .i_head     (i_head),
        .o_slip     (o_slip),
        .o_lock     (o_lock)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n      = 0;
        i_serdes_v = 0;
        i_valid    = 0;
        i_head     = '0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // helper: drive one header
    task automatic send_header(input logic [1:0] head);
        i_valid = 1;
        i_head  = head;
        @(posedge clk);
        i_valid = 0;
    endtask

    // helper: drive N consecutive valid headers (01 or 10, alternating)
    task automatic send_valid_headers(input int count);
        for (int i = 0; i < count; i++) begin
            send_header(i[0] ? 2'b01 : 2'b10);
        end
    endtask

    // --------------------------------------------------------------------------
    // isolated test: you're simulating the gearbox upstream (driving i_valid + i_head)
    // and simulating the SerDes status (driving i_serdes_v).
    //
    // this is a state machine; the tests need to exercise state transitions:
    //   LOCK_LOST -> BLOCK_LOCK (64 consecutive valid headers)
    //   BLOCK_LOCK -> LOCK_LOST (65 invalid headers in a window of 1024)
    //
    // *: o_slip should ONLY assert when i_valid is high. if it fires on a cycle
    //    where there's no valid header from the gearbox, you're slipping on garbage.
    //    check this explicitly.
    //
    // *: o_lock should reflect the current state. it's the first signal you'd
    //    monitor on real hardware: if it toggles, something is wrong.
    // --------------------------------------------------------------------------

    // test 1: lock acquisition : 64 valid headers
    //   i_serdes_v = 1, feed 64 consecutive valid headers (01 or 10).
    //   verify o_lock asserts after the 64th.
    //   verify o_slip never fires during this sequence.

    // test 2: lock acquisition : slip on invalid header
    //   i_serdes_v = 1, feed 30 valid headers, then 1 invalid (00 or 11).
    //   verify o_slip fires on the invalid header.
    //   verify o_lock stays low.
    //   verify the counter resets; need another 64 valid to lock.

    // test 3: lock acquisition -> multiple slips before lock
    //   feed patterns that cause 5 slips before 64 clean headers.
    //   verify each slip fires correctly and lock eventually asserts.

    // test 4: lock maintenance —> sparse invalid headers
    //   lock the module (64 valid headers).
    //   feed 1024 headers with 64 invalid ones spread throughout.
    //   verify o_lock stays high (64 < 65 threshold).
    //   *: the counter window is 1024. after 1024 headers, it resets.

    // test 5: lock loss —> 65 invalid in 1024 window
    //   lock the module.
    //   feed headers such that 65 are invalid within a 1024-header window.
    //   verify o_lock drops, o_slip fires, module returns to LOCK_LOST.

    // test 6: i_serdes_v gating
    //   lock the module, then drop i_serdes_v.
    //   verify o_lock drops immediately.
    //   reassert i_serdes_v, verify module starts acquisition from scratch.

    // test 7: i_valid gating
    //   hold i_valid low for 10 cycles while i_serdes_v is high.
    //   verify o_slip does NOT fire (no valid header to evaluate).
    //   verify the internal counter does not advance.

    // test 8: lock-loss-relock cycle
    //   lock -> lose lock via 65 bad headers -> relock with 64 good headers.
    //   verify the full round-trip works cleanly.

    initial begin
        $display("==============================================");
        $display("  block_sync isolated testbench");
        $display("==============================================");
        pass_count = 0;
        fail_count = 0;

        do_reset();
        i_serdes_v = 1;

        // implement tests here

        $display("\n==============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        $finish;
    end

endmodule
