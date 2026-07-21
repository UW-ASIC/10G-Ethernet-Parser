`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module scrambler_iso_tb;

    import eth_frame_pkg::*;

    localparam DATA_W = 64;

    logic                    clk;
    logic                    rst_n;
    logic                    i_valid;
    logic [DATA_W + 1 : 0]  i_enc_data;
    logic                    o_valid;
    logic [DATA_W + 1 : 0]  o_scram_data;

    scrambler #(.DATA_W(DATA_W)) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_valid      (i_valid),
        .i_enc_data   (i_enc_data),
        .o_valid      (o_valid),
        .o_scram_data (o_scram_data)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n     = 0;
        i_valid   = 0;
        i_enc_data = '0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // --------------------------------------------------------------------------
    // isolated test: no descrambler. you're simulating the encoder upstream
    // (driving i_valid + i_enc_data) and checking scrambler behavior directly.
    //
    // since there's no inverse to check against, what can you actually verify?
    //
    //   1. output should differ from input (scrambling actually happened)
    //   2. sync header [65:64] should pass through unchanged
    //   3. same input on two different cycles should produce different output
    //      (because LFSR state has advanced)
    //   4. o_valid should mirror i_valid with zero latency (combinational path)
    //   5. state should NOT update when i_valid is low
    //
    // *: to verify (5), feed block A, deassert valid for N cycles, feed block A
    //    again. if the output is the same both times, state didn't advance during
    //    the stall. if it's different, state leaked
    // --------------------------------------------------------------------------

    // test 1: output differs from input
    //   feed a known block, check o_scram_data[63:0] != i_enc_data[63:0].
    //   *: what if the input is all zeros? the XOR with LFSR state should still
    //      produce non-zero output (assuming state isn't also zero; it shouldn't
    //      be after reset).

    // test 2: sync header passthrough
    //   feed blocks with sync = 01, then 10.
    //   check o_scram_data[65:64] == i_enc_data[65:64] every cycle.

    // test 3: o_valid timing
    //   toggle i_valid on/off. verify o_valid follows immediately (same cycle).
    //   *: if o_valid lags by a cycle, the scrambler has an unintended register.

    // test 4: state freeze on stall
    //   feed block X. record output Y1.
    //   deassert i_valid for 5 cycles.
    //   feed block X again. record output Y2.
    //   Y1 should equal Y2 (state didn't advance during stall).

    // test 5: deterministic output after reset
    //   reset, feed a fixed sequence of 10 blocks. record all outputs.
    //   reset again, feed the same sequence. outputs should be bit-identical.
    //   *: this verifies reset actually clears state to a known value.

    // test 6: sustained stream (100+ blocks)
    //   feed random blocks continuously with i_valid high.
    //   verify no X's or Z's in output. verify o_valid stays high.

    initial begin
        $display("==============================================");
        $display("  scrambler isolated testbench");
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
