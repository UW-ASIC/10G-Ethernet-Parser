`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module scramblerxdescrambler_tb;

    import eth_frame_pkg::*;

    localparam DATA_W = 64;

    logic                    clk;
    logic                    rst_n;

    // scrambler side (driven by tb -> simulates encoder output)
    logic                    scram_i_valid;
    logic [DATA_W + 1 : 0]  scram_i_data;

    // scrambler -> descrambler interconnect (directly wired)
    logic                    scram_o_valid;
    logic [DATA_W + 1 : 0]  scram_o_data;

    // descrambler output (checked by tb)
    logic                    descram_o_valid;
    logic [DATA_W + 1 : 0]  descram_o_data;

    scrambler #(.DATA_W(DATA_W)) u_scram (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_valid      (scram_i_valid),
        .i_enc_data   (scram_i_data),
        .o_valid      (scram_o_valid),
        .o_scram_data (scram_o_data)
    );

    descrambler #(.DATA_W(DATA_W)) u_descram (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_valid        (scram_o_valid),
        .i_scram_data   (scram_o_data),
        .o_valid        (descram_o_valid),
        .o_descram_data (descram_o_data)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n = 0;
        scram_i_valid = 0;
        scram_i_data  = '0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // --------------------------------------------------------------------------
    // the core invariant: data fed into the scrambler should come out of
    // the descrambler bit-identical after the LFSR converges (~58 bits of state).
    //
    // *: the scrambler is combinational (zero latency), but think about whether
    //    the descrambler is too. if one of them registers output and the other
    //    doesn't, your comparison needs to account for that pipeline offset.
    //    don't just blindly compare same-cycle outputs.
    //
    // *: sync header bits [65:64] bypass both scrambler and descrambler.
    //    verify they come through unchanged regardless of payload content.
    // --------------------------------------------------------------------------

    // test 1: self-synchronization convergence
    //   feed N idle blocks, then switch to known data blocks.
    //   the first ~1-2 blocks after the scrambler state initializes may not
    //   descramble correctly (LFSR needs to fill). figure out exactly how many
    //   blocks it takes to converge by checking output against input.
    //
    // *: what does "converge" mean here? the descrambler state is built from
    //    received scrambled data. after 58 scrambled bits flow through (less
    //    than 1 full block), the descrambler's state matches the scrambler's.
    //    verify this: the FIRST block should already descramble correctly if
    //    both modules reset to the same initial state. if it doesn't, why?

    // test 2: continuous data stream
    //   feed 200+ random data blocks back to back with i_valid held high.
    //   every output (after convergence) should match the corresponding input.
    //   use a queue or shift register to store sent blocks and compare on arrival.

    // test 3: stall insertion
    //   randomly deassert i_valid for 1-3 cycles between blocks.
    //   the scrambler state should NOT update on invalid cycles.
    //   verify output data is still correct after stalls, should be the same data, just delayed.

    // test 4: mid-stream reset
    //   send 50 blocks, assert reset for 2 cycles, release, send 50 more.
    //   verify the second batch converges correctly from fresh state.
    //   *: both modules must re-converge after reset. how many blocks does that take?

    // test 5: sync header passthrough
    //   send blocks with different sync headers (01, 10) mixed with payloads.
    //   verify [65:64] of descrambler output always matches [65:64] of scrambler input,
    //   regardless of payload or scrambler state.

    // test 6: all-zeros and all-ones payloads
    //   constant payloads are degenerate cases for the LFSR.
    //   verify the round-trip still works.

    initial begin
        $display("==============================================");
        $display("  scrambler x descrambler testbench");
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
