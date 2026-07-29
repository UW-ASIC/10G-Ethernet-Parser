timescale 1ns/1ps

module CRC_core_tb;
    logic clk = 0;
    logic rstn = 0;
    logic [63:0] frame_word = 0;
    logic valid = 0, last = 0, corrupt = 0;
    logic [31:0] o_crc;
    int errors = 0;
    
    CRC_core dut(
        .i_clk(clk),
        .i_rstn(rstn),
        .i_8xframe(frame_word),
        .i_valid(valid),
        .i_last(last),
        .i_corrupt(corrupt),
        .o_crc(o_crc)
    );

    always #4 clk = ~clk;

    task send_beat(input logic [63:0] w, input logic last_b);
        begin
            frame_word <= w;
            valid <= 1;
            last <= last_b;
            @(posedge clk);
            valid <= 0;
            last <= 0;
        end
    endtask

    task check(input logic [31:0] expected, input string name);
        begin
            repeat (2) @(posedge clk);
            #1;
            if (o_crc === expected)
                $display("PASS %-22s o_crc = %08h", name, o_crc);
            else begin
                $display("FAIL %-22s o_crc = %08h, expected %08h", name, o_crc, expected);
                errors++;
            end
        end
    endtask

    initial begin
        $dumpfile("CRC_core_tb.vcd");
        $dumpvars(0, CRC_core_tb);

        repeat (4) @(posedge clk);
        rstn = 1;
        @(posedge clk);

        send_beat(64'h08_07_06_05_04_03_02_01, 1);
        check(32'h3FCA88C5, "8 bytes");

        send_beat(64'h48_47_46_45_44_43_42_41, 0);
        send_beat(64'h50_4F_4E_4D_4C_4B_4A_49, 1);
        check(32'hE0E8FF4D, "16 bytes");
            
        send_beat(64'h57_20_2C_6F_6C_6C_65_48, 0);
        send_beat(64'h26_5B_86_C6_64_6C_72_6F, 1);
        check(32'h2144DF1C, "data+FCS");

        corrupt <= 1;
        send_beat(64'h08_07_06_05_04_03_02_01, 1);
        corrupt <= 0;
        check(32'h3FCA88C5 ^ 32'h1, "corrupted");

        send_beat(64'h08_07_06_05_04_03_02_01, 1);
        check(32'h3FCA88C5, "after corrupt");

        if (errors == 0) $display("TESTS PASSED");
        else $display("%0d TESTS FAILED", errors);
        $finish;
    end

endmodule




