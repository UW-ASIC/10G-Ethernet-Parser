`timescale 1ns / 1ps
`include "eth_frame_pkg.sv"

module gearbox_txrx_tb;

    import eth_frame_pkg::*;

    localparam DATA_W = 64;
    localparam HEAD_W = 2;
    localparam BLOCK_W = DATA_W + HEAD_W;

    logic clk;
    logic rst_n;

    // gearbox_tx input (driven by tb — simulates scrambler output)
    logic [HEAD_W - 1 : 0]  tx_i_head;
    logic [DATA_W - 1 : 0]  tx_i_data;

    // gearbox_tx output -> gearbox_rx input (SerDes loopback)
    logic [DATA_W - 1 : 0]  serdes_data;
    logic                   tx_o_accept;

    // gearbox_rx control (driven by tb)
    logic                   rx_i_pma_lock;
    logic                   rx_i_slip;

    // gearbox_rx output (checked by tb)
    logic [BLOCK_W - 1 : 0] rx_o_data;
    logic                   rx_o_valid;
    logic [HEAD_W - 1 : 0]  rx_o_head;

    gearbox_tx #(.DATA_W(DATA_W), .HEAD_W(HEAD_W)) u_tx (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_head   (tx_i_head),
        .i_data   (tx_i_data),
        .o_data   (serdes_data),
        .o_accept (tx_o_accept)
    );

    gearbox_rx #(.DATA_W(DATA_W), .HEAD_W(HEAD_W)) u_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_data     (serdes_data),
        .i_pma_lock (rx_i_pma_lock),
        .i_slip     (rx_i_slip),
        .o_data     (rx_o_data),
        .o_valid    (rx_o_valid),
        .o_head     (rx_o_head)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    task automatic do_reset();
        rst_n        = 0;
        tx_i_head    = '0;
        tx_i_data    = '0;
        rx_i_pma_lock = 0;
        rx_i_slip    = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // --------------------------------------------------------------------------
    // loopback test: 66-bit blocks go into gearbox_tx, get packed into 64-bit
    // words on the "wire" (serdes_data), and gearbox_rx extracts them back.
    //
    // *: this is NOT plug-and-play. the RX gearbox doesn't magically know the
    //    alignment; it needs block_sync to find it via slip. in this tb, you
    //    have to drive i_slip manually to simulate what block_sync would do.
    //
    //    approach: let the RX free-run with pma_lock high. check o_head on each
    //    valid output. if the sync header isn't 01 or 10 (i.e., head[0] == head[1]),
    //    assert i_slip for one cycle. repeat until you see 64 consecutive valid
    //    headers. note that this is exactly what block_sync does— you're just doing it in
    //    the tb instead.
    //
    // *: gearbox_tx has a 1-cycle output register, so there's latency between
    //    feeding a block and it appearing on serdes_data. the RX side adds its
    //    own latency. account for this when comparing input blocks to output blocks.
    //
    // *: gearbox_tx asserts o_accept = 0 for one cycle every 33 cycles (buffer full).
    //    the RX side will see 33 output words per 32 input blocks, the extra word
    //    is the buffer drain. make sure your checking logic handles this asymmetry.
    // --------------------------------------------------------------------------

    // test 1: alignment acquisition
    //   feed idle blocks (sync = 10) continuously into TX.
    //   let RX free-run with pma_lock = 1.
    //   implement slip logic in the tb: check o_head, slip if invalid.
    //   measure how many slips it takes to lock. should be at most 65.
    //   once locked, verify 64+ consecutive valid headers.

    // test 2: data integrity after lock
    //   once aligned, feed 100+ known blocks (mix of sync=01 data blocks
    //   and sync=10 control blocks). collect RX output blocks.
    //   verify every extracted block matches what was fed in, in order.
    //   *: use a FIFO/queue to track sent blocks and compare on arrival.

    // test 3: backpressure handling
    //   verify TX's o_accept behavior: stays high for 32 cycles, drops for 1.
    //   feed blocks only when o_accept is high.
    //   verify RX still extracts correct blocks despite the periodic gap.

    // test 4: pma_lock deassert and reassert
    //   lock the RX, stream some data, drop pma_lock for 10 cycles, reassert.
    //   verify RX re-acquires alignment after pma_lock comes back.
    //   *: how many blocks does it take to re-lock?

    // test 5: sustained streaming
    //   500+ blocks, mixed data/control, with backpressure from TX.
    //   no errors should appear after initial lock.

    initial begin
        $display("==============================================");
        $display("  gearbox tx x rx loopback testbench");
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
