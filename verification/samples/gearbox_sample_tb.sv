`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module gearbox_tx_demo_tb;

    import eth_frame_pkg::*;

    localparam DATA_W  = 64;
    localparam HEAD_W  = 2;
    localparam BLOCK_W = DATA_W + HEAD_W;
    localparam N_BLOCKS = 128;

    logic                    clk;
    logic                    rst_n;
    logic [HEAD_W - 1 : 0]   i_head;
    logic [DATA_W - 1 : 0]   i_data;
    logic [DATA_W - 1 : 0]   o_data;
    logic                    o_accept;

    gearbox_tx #(.DATA_W(DATA_W), .HEAD_W(HEAD_W)) dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_head   (i_head),
        .i_data   (i_data),
        .o_data   (o_data),
        .o_accept (o_accept)
    );

    initial clk = 0;
    always #3.2 clk = ~clk;

    logic [BLOCK_W - 1 : 0] blocks [0 : N_BLOCKS - 1];
    int n_blocks;

    initial begin
        payload_t p;
        logic [BLOCK_W-1:0] frame_blocks [0:255];
        int n, idx = 0;

        while (idx < N_BLOCKS - 40) begin
            p = gen_random_payload($urandom_range(46, 200));
            n = build_frame_blocks(p, frame_blocks);
            for (int i = 0; i < n; i++)
                blocks[idx++] = frame_blocks[i];
            repeat ($urandom_range(2, 6))
                blocks[idx++] = idle_block();
        end
        n_blocks = idx;
    end

    // ========================================================================
    // PART 1: waveforms
    // ========================================================================
    initial begin
        $dumpfile("gearbox_tx_demo.vcd");
        $dumpvars(0, gearbox_tx_demo_tb);
    end

    initial begin
        rst_n  = 0;
        i_head = '0;
        i_data = '0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        for (int b = 0; b < n_blocks; b++) begin
            while (!o_accept) @(posedge clk);
            i_head = blocks[b][HEAD_W-1:0];
            i_data = blocks[b][BLOCK_W-1:HEAD_W];
            @(posedge clk);
        end

        repeat (10) @(posedge clk);
        $finish;
    end

    // ========================================================================
    // PART 2: log (uncomment to launch, comment out PART 1's $dumpvars block
    // if you only want console output)
    // ========================================================================
    // int word_count;
    //
    // always_ff @(posedge clk) begin
    //     if (rst_n) begin
    //         word_count <= word_count + 1;
    //         $display("[%0t] word %0d | o_data=%h | accept=%b", $time, word_count, o_data, o_accept);
    //         if (!o_accept)
    //             $display("[%0t] BUFFER DRAIN", $time);
    //     end
    // end
    //
    // initial begin
    //     word_count = 0;
    //     wait (rst_n);
    //     $display("[%0t] reset released", $time);
    // end

endmodule