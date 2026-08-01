'timescale 1ns/1ps
module frame_fcs_tb;

    logic clk = 0, rst_n = 0;
    logic [63:0] data;
    logic [7:0]  ctrl, keep;
    logic start, idle, terminate, error, tready;
    logic crc_in_valid, crc_valid, crc_ok;
    logic [63:0] tdata;
    logic [7:0]  tkeep;
    logic tvalid, tlast, tuser;

    always #5 clk = ~clk;

    mac_rx_crc dut (
        .clk (clk), 
        .rst_n (rst_n),
        .data (data),
        .ctrl (ctrl),
        .keep (keep),
        .start (start),
        .idle (idle),
        .terminate (terminate),
        .error (error),
        .crc_in_valid (crc_in_valid),
        .crc_valid (crc_valid),
        .crc_ok (crc_ok),
        .tready (tready),
        .tdata (tdata),
        .tkeep (tkeep),
        .tvalid (tvalid),
        .tlast (tlast),
        .tuser (tuser)
    );

    localparam int N_BEATS = 5;
    logic [63:0] beat_data [0:N_BEATS-1];
    logic [7:0]  beat_keep [0:N_BEATS-1];
    logic        beat_start [0:N_BEATS-1];
    logic        beat_idle [0:N_BEATS-1];
    logic        beat_term [0:N_BEATS-1];

    initial begin
        beat_data[0] = 64'hb1b0afaeadacabaa; beat_keep[0] = 8'hff;
        beat_start[0] = 1'b1; beat_idle[0] = 1'b0; beat_term[0] = 1'b0;

        beat_data[1] = 64'h0807060504030201; beat_keep[1] = 8'hff;
        beat_start[1] = 1'b0; beat_idle[1] = 1'b0; beat_term[1] = 1'b0;

        beat_data[2] = 64'h100f0e0d0c0b0a09; beat_keep[2] = 8'hff;
        beat_start[2] = 1'b0; beat_idle[2] = 1'b0; beat_term[2] = 1'b0;

        beat_data[3] = 64'heef8971514131211; beat_keep[3] = 8'hff;
        beat_start[3] = 1'b0; beat_idle[3] = 1'b0; beat_term[3] = 1'b0;

        beat_data[4] = 64'h000000000000000c; beat_keep[4] = 8'h01;
        beat_start[4] = 1'b0; beat_idle[4] = 1'b0; beat_term[4] = 1'b1;
    end

    initial begin
        crc_valid = 0; crc_ok = 0;
        forever begin   
            @(negedge crc_in_valid);
            repeat (5) @(posedge clk);
            crc_valid = 1;
            crc_ok = 1;
            @(posedge clk);
            crc_valid = 0;
        end
    end

    initial begin
        tready = 1;
        data = '0; ctrl = '0; keep = '0; start = 0; idle = 1; terminate = 0; error = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for(int i = 0; i < N_BEATS; i++) begin
            @(negedge clk);
            data = beat_data[i];
            keep = beat_keep[i];
            start = beat_start[i];
            idle = beat_idle[i];
            terminate = beat_term[i];
            error = 0;
        end
        @(negedge clk);
        data = '0; keep = '0; start = 0; idle = 1; terminate = 0;

        for(int i = 0; i < 15; i++) begin
            @(posedge clk);
            if (tvalid)
                $display("t=%0t tdata=%h tkeep=%h tlast=%b tuser=%b", 
                            $tim,, tdata, tkeep, tlast, tuser);
        end
        $finish;
    end
endmodule
