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
        rst_n      = 0;
        i_valid    = 0;
        i_enc_data = '0;
        repeat (2) @(posedge clk);
        rst_n = 1;
    endtask
    
    logic [65:0] Y1;
    logic [65:0] Y2;
    logic [65:0] Y3;
    logic [65:0] Y4;
    logic [65:0] Y5;
    logic [65:0] Y6;
    logic [65:0] Y7;
    logic [65:0] Y8;
    logic [65:0] Y9;
    logic [65:0] Y10;
    logic [65:0] Y11;
    logic [65:0] Y12;
    logic [65:0] Y13;
    logic [65:0] Y14;
    logic [65:0] Y15;
    logic [65:0] Y16;
    logic [65:0] Y17;
    logic [65:0] Y18;
    logic [65:0] Y19;
    logic [65:0] Y20;
    logic [65:0] w1;
    logic [65:0] w2;
    logic [65:0] w3;
    logic [65:0] w4;
    logic [65:0] w5;
    logic [65:0] w6;
    logic [65:0] w7;
    logic [65:0] w8;
    logic [65:0] w9;
    logic [65:0] w10;

    
    task automatic feed_10_row (
        input logic [65:0] w1,w2,w3,w4,w5,w6,w7,w8,w9,w10,
        output logic [65:0] y1,y2,y3,y4,y5,y6,y7,y8,y9,y10
    );
    
        @(posedge clk);
        do_reset();
        i_valid <= 1'b1;
        i_enc_data <= w1;
        @(negedge clk);
        y1 = o_scram_data;
        
        @(posedge clk);
        i_enc_data <= w2;
        @(negedge clk);
        y2 = o_scram_data;
        
        @(posedge clk);
        i_enc_data <= w3;
        @(negedge clk);
        y3 = o_scram_data;
        
        @(posedge clk);
        i_enc_data <= w4;
        @(negedge clk);
        y4 = o_scram_data;
        
        @(posedge clk);
        i_enc_data <= w5;
        @(negedge clk);
        y5 = o_scram_data;
        
        @(posedge clk);
        i_enc_data <= w6;
        @(negedge clk);
        y6 = o_scram_data;
        
        @(posedge clk);
        i_enc_data <= w7;
        @(negedge clk);
        y7 = o_scram_data;
        
        @(posedge clk);
        i_enc_data <= w8;
        @(negedge clk);
        y8 = o_scram_data;
        
        @(posedge clk);
        i_enc_data <= w9;
        @(negedge clk);
        y9 = o_scram_data;
        
        @(posedge clk);
        i_enc_data <= w10;
        @(negedge clk);
        y10 = o_scram_data;

        
    endtask
    
    // --------------------------------------------------------------------------
    // isolated test: no descrambler. you're simulating the encoder upstream
    // (driving i_valid + i_enc_data) and checking scrambler behavior directly.
    //
    // since there's no inverse to check against, what can you actually verify?
    //
    //   1. output should differ from input (scrambling actually happened)
    //   2. sync header [1:0] should pass through unchanged
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
    //   feed a known block, check o_scram_data[65:2] != i_enc_data[65:2].
    //   *: what if the input is all zeros? the XOR with LFSR state should still
    //      produce non-zero output (assuming state isn't also zero; it shouldn't
    //      be after reset).
    initial begin
    payload_t last_block;
    integer i;
    bit test6_failed;
    
    $display("==============================================");
    $display("  scrambler isolated testbench");
    $display("==============================================");
    pass_count = 0;
    fail_count = 0;

    do_reset();
    
    last_block = eth_frame_pkg::gen_random_payload(8);
    
    @(posedge clk);
    do_reset();
    
    @(posedge clk);
    
    @(posedge clk);
    i_valid    <= 1'b1;
    i_enc_data <= i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    
    repeat (2) @(posedge clk);
    i_valid <= 1'b0;
    if (o_scram_data !== i_enc_data) begin
        $display("  PASS [%s]: i_enc_data and o_scram_data were different", "test 1a");
        pass_count += 1;
    end else begin
        $display("  Fail [%s]: expected i_enc_data and o_scram_data to be different", "test 1a");
        fail_count += 1;
    end

    
    repeat (2) @(posedge clk);
    do_reset();
    
    repeat (2) @(posedge clk);
    i_valid <= 1'b1;
    i_enc_data <= '0;
    
    repeat (2) @(posedge clk);
    if (o_scram_data !== i_enc_data) begin
        $display("  PASS [%s]: i_enc_data and o_scram_data were different", "test 1b");
        pass_count += 1;
    end else begin
        $display("  Fail [%s]: expected i_enc_data and o_scram_data to be different", "test 1b");
        fail_count += 1;
    end
    
    repeat (2) @(posedge clk);
    do_reset();
    
    
    
    // test 2: sync header passthrough
    //   feed blocks with sync = 01, then 10.
    //   check o_scram_data[1:0] == i_enc_data[1:0] every cycle.

    last_block = eth_frame_pkg::gen_random_payload(8);
    
    @(posedge clk);
    do_reset();
    
    @(posedge clk);
    
    @(posedge clk);
    i_valid    <= 1'b1;
    i_enc_data <= i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    
    @(posedge clk);
    i_enc_data[1:0] <= 2'b10;
    
    repeat (2) @(posedge clk);
    i_valid <= 1'b0;
    if (o_scram_data[1:0] !== i_enc_data[1:0]) begin
        $display("  FAIL [%s]: i_enc_data[1:0] and o_scram_data[1:0] were different", "test 2a");
        fail_count += 1;
    end else begin
        $display("  PASS [%s]: i_enc_data[1:0] and o_scram_data[1:0] were the same", "test 2a");
        pass_count += 1;
    end

    
    repeat (2) @(posedge clk);
    do_reset();
    i_valid <= 1'b1;
    
    @(posedge clk);
    i_enc_data[1:0] <= 2'b01;
    
    repeat (2) @(posedge clk);
    i_valid <= 1'b0;
    if (o_scram_data[1:0] !== i_enc_data[1:0]) begin
        $display("  FAIL [%s]: i_enc_data[1:0] and o_scram_data[1:0] were different", "test 2b");
        fail_count += 1;
    end else begin
        $display("  PASS [%s]: i_enc_data[1:0] and o_scram_data[1:0] were the same", "test 2b");
        pass_count += 1;
    end
    
    repeat (2) @(posedge clk);
    do_reset();
    
    


    // test 3: o_valid timing
    //   toggle i_valid on/off. verify o_valid follows immediately (same cycle).
    //   *: if o_valid lags by a cycle, the scrambler has an unintended register.

    last_block = eth_frame_pkg::gen_random_payload(8);
    
    @(posedge clk);
    do_reset();
    
    repeat (2) @(posedge clk);
    i_valid <= 1'b1;
    #1;
    if (i_valid !== o_valid) begin
        $display("  FAIL [%s]: o_valid was not tracking i_valid", "test 3a");
        fail_count += 1;
    end else begin
        $display("  PASS [%s]: o_valid was tracking i_valid", "test 3a");
        pass_count += 1;
    end

    @(posedge clk);
    do_reset();
    
    @(posedge clk);
    i_valid <= 1'b1;
    
    repeat (2) @(posedge clk);
    i_valid <= 1'b0;
    @(negedge clk);
    if (i_valid !== o_valid) begin
        $display("  FAIL [%s]: o_valid was not tracking i_valid", "test 3b");
        fail_count += 1;
    end else begin
        $display("  PASS [%s]: o_valid was tracking i_valid", "test 3b");
        pass_count += 1;
    end

    @(posedge clk);
    do_reset();


    // test 4: state freeze on stall
    //   feed block X. record output Y1.
    //   deassert i_valid for 5 cycles.
    //   feed block X again. record output Y2.
    //   Y1 should equal Y2 (state didn't advance during stall).

    
    last_block = eth_frame_pkg::gen_random_payload(8);
    
    @(posedge clk);
    do_reset();
    
    @(posedge clk);
    
    @(posedge clk);
    i_valid    <= 1'b1;
    i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    
    @(posedge clk);
    i_valid <= 1'b0;
    @(negedge clk);
    Y1 = o_scram_data;
    

    repeat(5) @(posedge clk);

    @(negedge clk);
    Y2 = o_scram_data;
    
    repeat (2) @(posedge clk);
    if (Y1 !== Y2) begin
        $display("  FAIL [%s]: the state was not held constant during the stall", "test 4");
        fail_count += 1;
    end else begin
        $display("  PASS [%s]: the state was held constant during the stall", "test 4");
        pass_count += 1;
    end
    
    @(posedge clk);
    do_reset();
    
    // test 5: deterministic output after reset
    //   reset, feed a fixed sequence of 10 blocks. record all outputs.
    //   reset again, feed the same sequence. outputs should be bit-identical.
    //   *: this verifies reset actually clears state to a known value.
    @(posedge clk);
    last_block = eth_frame_pkg::gen_random_payload(8);
    w1 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    last_block = eth_frame_pkg::gen_random_payload(8);
    w2 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    last_block = eth_frame_pkg::gen_random_payload(8);
    w3 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    last_block = eth_frame_pkg::gen_random_payload(8);
    w4 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    last_block = eth_frame_pkg::gen_random_payload(8);
    w5 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    last_block = eth_frame_pkg::gen_random_payload(8);
    w6 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    last_block = eth_frame_pkg::gen_random_payload(8);
    w7 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    last_block = eth_frame_pkg::gen_random_payload(8);
    w8 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    last_block = eth_frame_pkg::gen_random_payload(8);
    w9 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    last_block = eth_frame_pkg::gen_random_payload(8);
    w10 = i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
    
    feed_10_row(.w1(w1), .w2(w2), .w3(w3), .w4(w4), .w5(w5), .w6(w6), .w7(w7), .w8(w8), .w9(w9), .w10(w10),
            .y1(Y1), .y2(Y2), .y3(Y3), .y4(Y4), .y5(Y5), .y6(Y6), .y7(Y7), .y8(Y8), .y9(Y9), .y10(Y10));
        
    @(posedge clk);
    feed_10_row(.w1(w1), .w2(w2), .w3(w3), .w4(w4), .w5(w5), .w6(w6), .w7(w7), .w8(w8), .w9(w9), .w10(w10),
            .y1(Y11), .y2(Y12), .y3(Y13), .y4(Y14), .y5(Y15), .y6(Y16), .y7(Y17), .y8(Y18), .y9(Y19), .y10(Y20));
        
    if ((Y1===Y11)&&(Y2===Y12)&&(Y3===Y13)&&(Y4===Y14)&&(Y5===Y15)&&(Y6===Y16)&&(Y7===Y17)&&(Y8===Y18)&&(Y9===Y19)&&(Y10===Y20)) begin
        $display("  PASS [%s]: state clears to known value.", "test 5");
        pass_count += 1;
    end else begin 
        $display("  FAIL [%s]: state clears to unknown value.", "test 5");
        fail_count += 1;
    end
    i_valid <= 1'b0;   

    // test 6: sustained stream (100+ blocks)
    //   feed random blocks continuously with i_valid high.
    //   verify no X's or Z's in output. verify o_valid stays high.
    test6_failed = 0;
    repeat (10) @(posedge clk);
    i_valid <= 1'b1;
    for (i=0; i < 2000; i++) begin
        last_block = eth_frame_pkg::gen_random_payload(8);
        @(posedge clk);
        i_enc_data <= i_enc_data <= {last_block.bytes[7], last_block.bytes[6], last_block.bytes[5], last_block.bytes[4], last_block.bytes[3], last_block.bytes[2], last_block.bytes[1], last_block.bytes[0], 2'b01};
        @(negedge clk);
        if ($isunknown(o_scram_data)) begin
            $display("  FAIL [%s]: unknown values in output.", "test 6");
            fail_count+=1;
            test6_failed = 1;
            break;
        end
        if (o_valid !== 1'b1) begin
            $display("  FAIL [%s]: o_valid dropped unexpectedly at iteration %0d", "test 6", i);
            fail_count += 1;
            test6_failed = 1;
            break;
        end
    end
    
    if (!test6_failed) begin
        $display("  PASS [%s]: 100+ blocks processed with no X/Z and valid remained high", "test 6");
        pass_count += 1;
    end
    
        $display("\n==============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        $finish;
    end

endmodule
