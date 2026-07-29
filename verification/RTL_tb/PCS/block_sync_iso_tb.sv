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

    bit slip_seen;
    always @(posedge o_slip) slip_seen = 1'b1;
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
        // i_valid = 0;
    endtask

    // helper: drive N consecutive valid headers (01 or 10, alternating)
    task automatic send_valid_headers(input int count);
        for (int i = 0; i < count; i++) begin
            send_header(i[0] ? 2'b01 : 2'b10);
        end
    endtask

    task automatic send_header_with_errors(input int total, input int bad_count);
        bit is_bad[int];
        real stride;


        stride = real'(total) / real'(bad_count);
        for (int i = 0; i < bad_count; i++) begin
            is_bad[int'(i * stride)] = 1'b1;
        end

        for(int i = 0; i < total; i++) begin
            if(is_bad.exists(i)) begin
                send_header(2'b11);
            end else begin
                send_header(i[0] ? 2'b01 : 2'b10);
            end
        end
    endtask 
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

        task automatic test_lock_acquisition_valid_header();
            $display("\n[TEST 1] o_lock asserts after 64th header & o_slip doesn't fire through sequence");

            do_reset();
            i_serdes_v = 1;

            send_valid_headers(64);

            if(o_lock == 1'b1) begin
                $display("TEST PASSED: o_lock asserts after 64th header");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock not asserted after 64th header");
                fail_count++;
            end

            if(o_slip == 1'b0) begin
                $display("TEST PASSED: o_slip is never fired");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_slip fired");
                fail_count++;
            end


        endtask 

    // test 2: lock acquisition : slip on invalid header
    //   i_serdes_v = 1, feed 30 valid headers, then 1 invalid (00 or 11).
    //   verify o_slip fires on the invalid header.
    //   verify o_lock stays low.
    //   verify the counter resets; need another 64 valid to lock.
        task automatic test_lock_acquisition_slip_invalid_header();
            $display("\n[TEST 2] o_slip fires on invalid header");

            do_reset();
            i_serdes_v = 1;

            send_valid_headers(30);

            i_valid = 1'b1;
            i_head = 2'b11;
            @(posedge clk);
            
            if(o_slip == 1'b1) begin
                $display("TEST PASSED: o_slip fires on invalid header");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_slip doesn't fire on invalid header");
                fail_count++;
            end

            if(o_lock == 1'b0) begin
                $display("TEST PASSED: o_lock stays low on invalid header");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock asserts on invalid header");
                fail_count++;
            end

            if(dut.counter == '0) begin
                $display("TEST PASSED: Counter resets, requires another 64 valid headers");
                pass_count++;
            end else begin
                $display("TEST FAILED: Counter doesn't reset");
                fail_count++;
            end

            i_valid = 1'b0;
        endtask 
    // test 3: lock acquisition -> multiple slips before lock
    //   feed patterns that cause 5 slips before 64 clean headers.
    //   verify each slip fires correctly and lock eventually asserts.
        task automatic test_lock_acquisition_multiple_slip();
            $display("\n[TEST 3] o_slip fires on invalid header");

            do_reset();
            i_serdes_v = 1;

            for(int i = 0; i < 5; i++) begin
                i_valid = 1'b1;
                i_head = 2'b11;
                @(posedge clk);
                
                if(o_slip == 1'b1) begin
                    $display("TEST PASSED: o_slip fires invalid header #%d", i);
                    pass_count++;
                end else begin
                    $display("TEST FAILED: o_slip doesn't fire on invalid header #%d", i);
                    fail_count++;
                end

                i_valid = 1'b0;

                @(posedge clk);
            end

            send_valid_headers(64);

            if(o_lock == 1'b1) begin
                $display("TEST PASSED: o_lock asserts after 64th header");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock not asserted after 64th header");
                fail_count++;
            end

        endtask 
    // test 4: lock maintenance —> sparse invalid headers
    //   lock the module (64 valid headers).
    //   feed 1024 headers with 64 invalid ones spread throughout.
    //   verify o_lock stays high (64 < 65 threshold).
    //   *: the counter window is 1024. after 1024 headers, it resets.
        task automatic test_lock_maintenance_sparse_invalid_headers();
            $display("\n[TEST 4] Lock maintenance: Sparse invalid headers");

            do_reset();
            i_serdes_v = 1;

            send_valid_headers(64);
            send_header_with_errors(1024, 64);

            if(o_lock == 1'b1) begin
                $display("TEST PASSED: o_lock stays high");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock goes low, threshold violated");
                fail_count++;
            end

        endtask 

    // test 5: lock loss —> 65 invalid in 1024 window
    //   lock the module.
    //   feed headers such that 65 are invalid within a 1024-header window.
    //   verify o_lock drops, o_slip fires, module returns to LOCK_LOST.
        task automatic test_lock_loss_65_invalid_1024_window();
            $display("\n[TEST 5] Lock loss: 65 invalid headers in 1024 window");

            do_reset();
            i_serdes_v = 1;

            send_valid_headers(64);
            
            slip_seen = 1'b0;
            send_header_with_errors(1024, 65);

            if(o_lock == 1'b0) begin
                $display("TEST PASSED: o_lock is dropped");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock does not drop");
                fail_count++;
            end

            if(slip_seen == 1'b1) begin
                $display("TEST PASSED: o_slip fires on invalid header");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_slip doesn't fire on invalid header");
                fail_count++;
            end
            
            if(dut.current_state == dut.LOCK_LOST) begin
                $display("TEST PASSED: Block_Sync returns to LOCK_LOST state");
                pass_count++;
            end else begin
                $display("TEST FAILED: Block_Sync stays in BLOCK_LOCK state");
                fail_count++;
            end

        endtask 
    // test 6: i_serdes_v gating
    //   lock the module, then drop i_serdes_v.
    //   verify o_lock drops immediately.
    //   reassert i_serdes_v, verify module starts acquisition from scratch.
    task automatic test_i_serdes_v_gating();
            $display("\n[TEST 6] i_serdes_v gating");

            do_reset();
            i_serdes_v = 1;

            send_valid_headers(64);
            
            i_serdes_v = 0;
            @(posedge clk);

            if(o_lock == 1'b0) begin
                $display("TEST PASSED: o_lock is dropped");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock does not drop");
                fail_count++;
            end
            
            i_serdes_v = 1;

            send_valid_headers(63);

            if(o_lock == 1'b0) begin
                $display("TEST PASSED: o_lock stays low after 63 headers(reacquisition not yet complete)");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock does not drop");
                fail_count++;
            end

            i_valid = 1'b1;
            i_head = 2'b10;
            @(posedge clk);

            if(o_lock == 1'b1) begin
                $display("TEST PASSED: o_lock asserts after 64th header");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock not asserted after 64th header");
                fail_count++;
            end
        endtask     
    // test 7: i_valid gating
    //   hold i_valid low for 10 cycles while i_serdes_v is high.
    //   verify o_slip does NOT fire (no valid header to evaluate).
    //   verify the internal counter does not advance.
task automatic test_i_valid_gating();
    int current_count;

    $display("\n[TEST 7] i_valid gating");

    do_reset();
    i_serdes_v = 1;

    send_valid_headers(5);
    i_valid = 0;
    current_count = dut.counter;

    for (int i = 0; i < 10; i++) begin
        @(posedge clk);
    end

    if (o_slip == 1'b0) begin
        $display("TEST PASSED: o_slip does not fire (no valid header to evaluate)");
        pass_count++;
    end else begin
        $display("TEST FAILED: o_slip fires");
        fail_count++;
    end

    if (current_count == dut.counter) begin
        $display("TEST PASSED: counter stays flat, does not advance");
        pass_count++;
    end else begin
        $display(
            "TEST FAILED: counter advances from %0d to %0d",
            current_count,
            dut.counter
        );
        fail_count++;
    end
endtask
    // test 8: lock-loss-relock cycle
    //   lock -> lose lock via 65 bad headers -> relock with 64 good headers.
    //   verify the full round-trip works cleanly.
        task automatic test_lock_loss_relock_cycle();
            $display("\n[TEST 8] lock-loss-relock cycle");
        
            do_reset();
            i_serdes_v = 1;

            send_valid_headers(64);

            if(o_lock == 1'b1) begin
                $display("TEST PASSED: o_lock asserts after 64th header");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock not asserted after 64th header");
                fail_count++;
            end
            
            if(o_slip == 1'b0) begin
                $display("TEST PASSED: o_slip is never fired");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_slip fired");
                fail_count++;
            end

            slip_seen = 1'b0;
            send_header_with_errors(1024, 65);

            if(o_lock == 1'b0) begin
                $display("TEST PASSED: o_lock is dropped");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock does not drop");
                fail_count++;
            end

            if(slip_seen == 1'b1) begin
                $display("TEST PASSED: o_slip fires on invalid header");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_slip doesn't fire on invalid header");
                fail_count++;
            end
            
            if(dut.current_state == dut.LOCK_LOST) begin
                $display("TEST PASSED: Block_Sync returns to LOCK_LOST state");
                pass_count++;
            end else begin
                $display("TEST FAILED: Block_Sync stays in BLOCK_LOCK state");
                fail_count++;
            end

            send_valid_headers(64);

            if(o_lock == 1'b1) begin
                $display("TEST PASSED: o_lock asserts after 64th header");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_lock not asserted after 64th header");
                fail_count++;
            end
            
            if(o_slip == 1'b0) begin
                $display("TEST PASSED: o_slip is never fired");
                pass_count++;
            end else begin
                $display("TEST FAILED: o_slip fired");
                fail_count++;
            end
        endtask
    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, block_sync_iso_tb);

        $display("==============================================");
        $display("  block_sync isolated testbench");
        $display("==============================================");
        pass_count = 0;
        fail_count = 0;

        do_reset();
        i_serdes_v = 1;

        // implement tests here
        test_lock_acquisition_valid_header();
        test_lock_acquisition_slip_invalid_header();
        test_lock_acquisition_multiple_slip();
        test_lock_maintenance_sparse_invalid_headers();
        test_lock_loss_65_invalid_1024_window();
        test_i_serdes_v_gating();
        test_i_valid_gating();
        test_lock_loss_relock_cycle();

        $display("\n==============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        $finish;
    end

endmodule
