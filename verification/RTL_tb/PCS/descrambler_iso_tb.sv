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
    task automatic latency_measurement();
        logic [65:0] random_block;

        $display("\n[TEST 1] OUTPUT latency measurement");

        do_reset();
        random_block = random_data_block();
        @(negedge clk);
            i_valid      = 1'b1;
            i_scram_data = random_block;
            #1;
        if (o_valid === 1'b1) begin
            $display("Output is valid before posedge (combinational)");
            fail_count++;
        end
        else begin
            $display("No combinational output");
        end
        @(posedge clk);
        #1;
        if (o_valid === 1'b1) begin
            $display("Output appears on next posedge (registered)");
            pass_count++;
        end
        else begin
            $display("No output on next posedge");
            fail_count++;

        end



    endtask

    // test 2: sync header passthrough
    //   same as scrambler; verify [65:64] pass through for both 01 and 10.
    task automatic sync_header_passthrough();
        logic [65:0] random_block;
        random_block = random_data_block();
        $display("\n[TEST 2] passthrough for 01");

        do_reset();

        
        //01 HEADER PASSTHROUGH 
        @(negedge clk);
        i_valid = 1'b1;
        i_scram_data = random_block;
        @(posedge clk);
        #1;
        if(o_descram_data[1:0] == 2'b01) begin
            $display("\n[TEST 2] passthrough PASS for 01");
            pass_count++;
        end else begin
            fail_count++;
            $display("\n[TEST 2] passthrough FAIL for 01");
        end

        do_reset();
        random_block[1:0] = 2'b10;
        
        //10 HEADER PASSTHROUGH
        @(negedge clk);
        i_valid = 1'b1;
        i_scram_data = random_block;
        @(posedge clk);
        #1;
        if(o_descram_data[1:0] == 2'b10) begin
            $display("\n[TEST 2] passthrough PASS for 10");
            pass_count++;
        end else begin
            fail_count++;
            $display("\n[TEST 2] passthrough FAIL for 10");
        end
    endtask
    // test 3: state freeze on stall
    //   feed block X, deassert valid, feed block X again.
    //   output should be identical both times (state frozen during stall).
    task automatic state_freeze_on_stall();
        logic [65:0] new_input_block, state_block;
        logic [65:0] output_A, output_B;
        $display("\n[TEST 3] state freeze on stall");
        do_reset();

        //input to compare output A (before stall) and output B (after stall)
        new_input_block = random_data_block();
        state_block = random_data_block();

        //SETTING INITIAL STATE
        @(negedge clk);
        i_valid      = 1'b1;
        i_scram_data = state_block; //Feed random state block X
        //state block X gets stored in state, output is based on state= '1;

        //OUTPUT A (before stall). State should be based on state_block;
        @(negedge clk);
        i_valid = 1'b1;
        i_scram_data = state_block;
        @(posedge clk);
        #1;
        output_A = o_descram_data;

        //STALL. State should NOT update
        @(negedge clk);
        i_valid = 1'b0;
        i_scram_data = new_input_block; 

        //State should be based on state_block
        @(negedge clk);
        i_valid = 1'b1;
        i_scram_data = state_block;
        @(posedge clk);
        #1;
        output_B = o_descram_data;

        if(check_match(output_A, output_B, "[TEST 3] State Freeze")) begin
            $display("[TEST 3] State freeze PASS");
            pass_count++;
        end
        else begin
            $display("[TEST 3] State freeze FAIL");
            fail_count ++;
        end
    endtask
    // test 4: deterministic output after reset
    //   reset, feed fixed sequence, record outputs.
    //   reset, feed same sequence, verify identical outputs.
    task automatic deterministic_output_after_reset();
        logic [65:0] output_A, output_B;
        logic [65:0] data_block;
        
        $display("\n[TEST 4] deterministic output after reset PASS");
        
        data_block = random_data_block();
        

        //FIRST RESET
        do_reset();
        @(negedge clk);
        i_valid = 1'b1;
        i_scram_data = data_block;
        @(posedge clk);
        #1;
        output_A = o_descram_data;

        //SECOND RESET
        do_reset();
        @(negedge clk);
        i_valid = 1'b1;
        i_scram_data = data_block;
        @(posedge clk);
        #1;
        output_B = o_descram_data;

        if(check_match(output_A, output_B, "TEST [4] deterministic reset")) begin
            $display("[TEST 4] deterministic output after reset PASS");
            pass_count++;
        end
        else begin
            $display("[TEST 4] deterministic output after reset FAIL");
            fail_count ++;
        end
    endtask

    
    // test 5: known-value test
    //   feed all zeros. the descrambler XORs input with LFSR state.
    //   after reset, state = all-ones 
    //   so the first output should be the XOR of all-zeros with the initial state
    //   you can compute the expected output by hand for the first block.
    //   *: this is the strongest isolated test you can write without a scrambler
    task automatic known_value_test();
        logic [65:0] descram_output;
        logic [65:0] data_block;

        $display("\n[TEST 5] known-value test");

        //RESET
        do_reset();
        //FEED ZEROES
        @(negedge clk);
        i_valid = 1'b1;
        i_scram_data = '0;
        @(posedge clk);
        #1;

        //EXPECT 63:58 = 0, 57:39 =1 38:0 = 0
        descram_output = o_descram_data;
        if(descram_output == {6'b0, 19'h7FFFF, 39'b0, 2'b00}) begin
            $display("[TEST 5] known value test PASS");
            pass_count ++;
        end else begin
            $display("[TEST 5] known value test FAIL");
            fail_count ++;
        end
    endtask
    // test 6: sustained stream
    //   100+ random blocks, verify no X's or Z's, verify o_valid behavior.
    task automatic sustained_stream_test();
        logic [65:0] data_block;
        logic fail_flag = 1'b0;
        
       $display("\n[TEST 6] sustained stream test");
       
       do_reset();
        repeat(100) begin
            data_block = random_data_block();
            @(negedge clk);

            i_valid = $urandom_range(0,1);
            i_scram_data = data_block;
            @ (posedge clk);
            #1;
            if($isunknown(o_valid)) begin
                $display("o_valid contains X or Z");
                fail_flag = 1'b1;
                break;
            end else if(o_valid != i_valid) begin
                $display("o_valid is different from i_valid");
                fail_flag = 1'b1;
                break;
            end else if(o_valid && $isunknown(o_descram_data)) begin
                $display("o_descram_data countains X or Z");
                fail_flag = 1'b1;
                break;
            end
        end
        if(fail_flag==1'b1) begin
            $display("[TEST 6] Sustained stream test FAIL");
            fail_count++;
        end else begin
            $display("[TEST 6] Sustained stream test PASS");
            pass_count++;
        end
    endtask

    initial begin
        $display("==============================================");
        $display("  descrambler isolated testbench");
        $display("==============================================");
        pass_count = 0;
        fail_count = 0;

        do_reset();

        // implement tests here
        latency_measurement();
        sync_header_passthrough();
        state_freeze_on_stall();
        deterministic_output_after_reset();
        known_value_test();
        sustained_stream_test();
        $display("\n==============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        $finish;
    end

endmodule