`timescale 1ns / 1ps

module PCS_top_wrapper (
    input  logic clk,
    output logic pin_out   // single output to prevent global trim
);

    //=== internal reset 
    logic [3:0] rst_sr = 4'b0;
    wire rst_n = rst_sr[3];
    always_ff @(posedge clk)
        rst_sr <= {rst_sr[2:0], 1'b1};

    //=== LFSR stimulus (drives all DUT inputs)
    (* DONT_TOUCH = "TRUE" *) logic [63:0] lfsr;
    always_ff @(posedge clk) begin
        if (!rst_n)
            lfsr <= 64'hDEAD_BEEF_CAFE_BABE;
        else
            lfsr <= {lfsr[62:0], lfsr[63] ^ lfsr[62] ^ lfsr[60] ^ lfsr[59]};
    end

    //=== DUT
    logic [63:0] serdes_tx;
    logic        tx_accept;
    logic        rx_valid;
    logic [63:0] rx_data;
    logic [7:0]  rx_ctrl;
    logic [7:0]  rx_keep;
    logic        rx_start, rx_idle, rx_term, rx_error;
    logic        blk_lock;

    (* DONT_TOUCH = "TRUE" *)
    PCS_top #(.DATA_W(64), .HEAD_W(2)) u_pcs (
        .clk             (clk),
        .rst_n           (rst_n),

        .serdes_rx_data  (lfsr),
        .serdes_rx_lock  (rst_n),
        .serdes_tx_data  (serdes_tx),

        .mac_tx_valid    (lfsr[0]),
        .mac_tx_data     (lfsr),
        .mac_tx_ctrl     (lfsr[7:0]),
        .mac_tx_keep     (lfsr[15:8]),
        .mac_tx_start    (lfsr[16]),
        .mac_tx_idle     (lfsr[17]),
        .mac_tx_terminate(lfsr[18]),
        .mac_tx_error    (lfsr[19]),
        .mac_tx_accept   (tx_accept),

        .mac_rx_valid    (rx_valid),
        .mac_rx_data     (rx_data),
        .mac_rx_ctrl     (rx_ctrl),
        .mac_rx_keep     (rx_keep),
        .mac_rx_start    (rx_start),
        .mac_rx_idle     (rx_idle),
        .mac_rx_terminate(rx_term),
        .mac_rx_error    (rx_error),

        .block_lock      (blk_lock)
    );

    //=== signature register (output capture)
    (* DONT_TOUCH = "TRUE" *) logic [63:0] sig;
    always_ff @(posedge clk) begin
        if (!rst_n)
            sig <= '0;
        else
            sig <= sig ^ serdes_tx ^ rx_data
                       ^ {56'b0, rx_ctrl}
                       ^ {56'b0, rx_keep}
                       ^ {63'b0, rx_valid ^ rx_start ^ rx_idle ^ rx_term ^ rx_error ^ blk_lock ^ tx_accept};
    end

    assign pin_out = sig[0];

endmodule