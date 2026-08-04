`timescale 1ns / 1ps

//==========================================
// Testbench for IP Parser IHL Decoder
//==========================================

module tb_ip_parser_ihl_decoder ();

    // DUT Interface Signals
    logic [3:0] ihl;
    logic [5:0] header_len_bytes;
    logic [2:0] header_end_beat;
    logic [2:0] header_end_offset;
    logic       ihl_invalid;

    // DUT Instantiation
    ip_parser_ihl_decoder dut (
        .ihl               (ihl),
        .header_len_bytes  (header_len_bytes),
        .header_end_beat   (header_end_beat),
        .header_end_offset (header_end_offset),
        .ihl_invalid       (ihl_invalid)
    );

    // Score and test tracking
    integer errors = 0;

    // Same if/else helper style as tb_ip_parser_input_fifo.sv
    task check(input cond, input string msg);
        if (cond)
            $display("PASS: %0s", msg);
        else begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask

    // Main Test Flow
    initial begin
        $dumpfile("tb_ip_parser_ihl_decoder.vcd");
        $dumpvars(0, tb_ip_parser_ihl_decoder);

        // ====================================
        // Test 1: ihl = 5, the only valid case
        // ====================================
        $display("\n[TB] === Test 1: ihl = 5 (standard header, no options) ===");

        ihl = 5;
        #10;

        check(header_len_bytes == 20, "header_len_bytes == 20 for ihl=5");
        check(header_end_beat == 2, "header_end_beat == 2 for ihl=5");
        check(header_end_offset == 4, "header_end_offset == 4 for ihl=5");
        check(ihl_invalid == 0, "ihl_invalid == 0 for ihl=5");

        // ====================================
        // Test 2: ihl = 6, one word of options
        // ====================================
        $display("\n[TB] === Test 2: ihl = 6 (options present) ===");

        ihl = 6;
        #10;

        check(header_len_bytes == 24, "header_len_bytes == 24 for ihl=6");
        check(header_end_beat == 3, "header_end_beat == 3 for ihl=6");
        check(header_end_offset == 0, "header_end_offset == 0 for ihl=6");
        check(ihl_invalid == 1, "ihl_invalid == 1 for ihl=6 (unsupported by checksum)");

        // ===============================
        // Test 3: ihl = 0, malformed case
        // ===============================
        $display("\n[TB] === Test 3: ihl = 0 (malformed) ===");

        ihl = 0;
        #10;

        check(header_len_bytes == 0, "header_len_bytes == 0 for ihl=0");
        check(ihl_invalid == 1, "ihl_invalid == 1 for ihl=0");

        // =============================================
        // Test 4: ihl = 15, max possible header length
        // =============================================
        $display("\n[TB] === Test 4: ihl = 15 (max header length) ===");

        ihl = 15;
        #10;

        check(header_len_bytes == 60, "header_len_bytes == 60 for ihl=15");
        check(header_end_beat == 7, "header_end_beat == 7 for ihl=15");
        check(header_end_offset == 4, "header_end_offset == 4 for ihl=15");
        check(ihl_invalid == 1, "ihl_invalid == 1 for ihl=15");

        // --- Summary ---
        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end
endmodule

/*
VERILATOR COMMAND TEST
verilator --binary -j 0 --timing --trace --trace-structs -Wall -Wno-fatal RTL/IP_Parser/ip_parser_ihl_decoder.sv verification/IP_Parser/tb_ip_parser_ihl_decoder.sv --top-module tb_ip_parser_ihl_decoder

RUN TEST
./obj_dir/Vtb_ip_parser_ihl_decoder
*/