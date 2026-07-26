`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module descrambler_iso_tb;

    import eth_frame_pkg::*;

    localparam DATA_W = 64;

    logic                    clk;
    logic                    rst_n;
    logic                    i_valid;
    logic [DATA_W + 1 : 0]  i_scram_data;
    logic                    o_valid;
    logic [DATA_W + 1 : 0]  o_descram_data;

    descrambler #(.DATA_W(DATA_W)) dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_valid        (i_valid),
        .i_scram_data   (i_scram_data),
        .o_valid        (o_valid),
        .o_descram_data (o_descram_data)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n        = 0;
        i_valid      = 0;
        i_scram_data = '0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // --------------------------------------------------------------------------
    // isolated test: no scrambler. you're simulating the gearbox upstream
    // (driving i_valid + i_scram_data) and checking descrambler output directly.
    //
    // without the scrambler's actual output to feed in, you can't verify correct
    // descrambling end-to-end. but you CAN verify the module's behavior:
    //
    //   1. sync header passthrough: [65:64] unchanged
    //   2. state tracks INPUT (not output) —> key difference from the scrambler
    //   3. o_valid timing relative to i_valid
    //   4. state doesn't update on invalid cycles
    //   5. deterministic output from deterministic input after reset
    //
    // *: check whether o_valid and o_descram_data are registered or combinational.
    //    the scrambler is combinational. if the descrambler is registered, there's
    //    a 1-cycle pipeline offset in the RX path. this isn't necessarily wrong,
    //    but it IS a difference you should document and verify intentionally.
    //    (hint: feed a block and check if the output changes same cycle or next.)
    // --------------------------------------------------------------------------

    // test 1: output latency measurement
    //   feed one block. check: does o_descram_data update on the same posedge,
    //   or on the next? this tells you if the output is registered.
    //   *: compare this to the scrambler. are they consistent?

    // test 2: sync header passthrough
    //   same as scrambler; verify [65:64] pass through for both 01 and 10.

    // test 3: state freeze on stall
    //   feed block X, deassert valid, feed block X again.
    //   output should be identical both times (state frozen during stall).

    // test 4: deterministic output after reset
    //   reset, feed fixed sequence, record outputs.
    //   reset, feed same sequence, verify identical outputs.

    // test 5: known-value test
    //   feed all zeros. the descrambler XORs input with LFSR state.
    //   after reset, state = all-ones 
    //   so the first output should be the XOR of all-zeros with the initial state
    //   you can compute the expected output by hand for the first block.
    //   *: this is the strongest isolated test you can write without a scrambler

    // test 6: sustained stream
    //   100+ random blocks, verify no X's or Z's, verify o_valid behavior.

    initial begin
        $display("==============================================");
        $display("  descrambler isolated testbench");
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
