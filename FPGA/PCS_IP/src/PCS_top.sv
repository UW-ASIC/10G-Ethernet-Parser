module PCS_top #(
    parameter DATA_W = 64,
    parameter HEAD_W =  2
)(
    input  logic    clk,
    input  logic  rst_n,

    //=== SerDes (RX in, TX out)
    input  logic [DATA_W-1:0]   serdes_rx_data,
    input  logic                serdes_rx_lock,
    output logic [DATA_W-1:0]   serdes_tx_data,

    //=== MAC TX (in from MAC, accept out)
    input  logic                mac_tx_valid,
    input  logic [DATA_W-1:0]   mac_tx_data,
    input  logic [7:0]          mac_tx_ctrl,
    input  logic [7:0]          mac_tx_keep,
    input  logic                mac_tx_start,
    input  logic                mac_tx_idle,
    input  logic                mac_tx_terminate,
    input  logic                mac_tx_error,
    output logic                mac_tx_accept,

    //=== MAC RX (out to MAC)
    output logic                mac_rx_valid,
    output logic [DATA_W-1:0]   mac_rx_data,
    output logic [7:0]          mac_rx_ctrl,
    output logic [7:0]          mac_rx_keep,
    output logic                mac_rx_start,
    output logic                mac_rx_idle,
    output logic                mac_rx_terminate,
    output logic                mac_rx_error,

    //=== Status
    output logic                block_lock
);

    localparam BLOCK_W = DATA_W + HEAD_W;



    //  TX PATH: MAC → encoder → scrambler → gearbox_tx → SerDes

    //=== encoder ↔ scrambler
    logic enc_valid;
    logic [65:0]   enc_data;

    //=== scrambler ↔ gearbox_tx
    logic       scram_valid;
    logic [65:0] scram_data;

    //=== gearbox_tx backpressure
    logic         tx_accept;

    //=== gate encoder valid with gearbox backpressure:
    //=== encoder and scrambler are combinational, so we gate at the source
    wire tx_valid_gated;
    assign tx_valid_gated = mac_tx_valid & tx_accept;


    (* DONT_TOUCH = "TRUE" *)
    encoder #(.DATA_W(DATA_W)) encoder_inst (
        .clk                      (clk),
        .rst_n                  (rst_n),
        .i_valid       (tx_valid_gated),
        .i_data           (mac_tx_data),
        .i_ctrl           (mac_tx_ctrl),
        .i_keep           (mac_tx_keep),
        .i_start         (mac_tx_start),
        .i_idle           (mac_tx_idle),
        .i_terminate (mac_tx_terminate),
        .i_error         (mac_tx_error),
        .o_valid            (enc_valid),
        .o_data              (enc_data)
    );

    (* DONT_TOUCH = "TRUE" *)
    scrambler #(.DATA_W(DATA_W)) scrambler_inst (
        .clk                      (clk),
        .rst_n                  (rst_n),
        .i_valid            (enc_valid),
        .i_enc_data          (enc_data),
        .o_valid          (scram_valid),
        .o_scram_data      (scram_data)
    );

    (* DONT_TOUCH = "TRUE" *)
    gearbox_tx #(.DATA_W(DATA_W), .HEAD_W(HEAD_W)) gearbox_tx_inst (
        .clk                      (clk),
        .rst_n                  (rst_n),
        .i_head       (scram_data[1:0]),
        .i_data      (scram_data[65:2]),
        .o_data        (serdes_tx_data),
        .o_accept           (tx_accept)
    );

    assign mac_tx_accept  =  tx_accept;



    //  RX PATH: SerDes → gearbox_rx & block_sync → descrambler → decoder → MAC


    //=== gearbox_rx outputs
    logic [BLOCK_W-1:0] gb_rx_data;
    logic              gb_rx_valid;
    logic [HEAD_W-1:0]  gb_rx_head;

    //=== block_sync outputs
    logic  bs_slip;
    logic  bs_lock;

    //=== descrambler outputs
    logic       descram_valid;
    logic [65:0] descram_data;

    (* DONT_TOUCH = "TRUE" *)
    gearbox_rx #(.DATA_W(DATA_W), .HEAD_W(HEAD_W)) gearbox_rx_inst (
        .clk                   (clk),
        .rst_n               (rst_n),
        .i_data     (serdes_rx_data),
        .i_pma_lock (serdes_rx_lock),
        .i_slip            (bs_slip),
        .o_data         (gb_rx_data),
        .o_valid       (gb_rx_valid),
        .o_head         (gb_rx_head)
    );

    (* DONT_TOUCH = "TRUE" *)
    block_sync_rx #(.HEAD_W(HEAD_W)) block_sync_inst (
        .clk                   (clk),
        .rst_n               (rst_n),
        .i_serdes_v (serdes_rx_lock),
        .i_valid       (gb_rx_valid),
        .i_head         (gb_rx_head),
        .o_slip            (bs_slip),
        .o_lock            (bs_lock)
    );

    // only feed descrambler once block lock is achieved
    wire rx_data_valid = gb_rx_valid & bs_lock;

    (* DONT_TOUCH = "TRUE" *)    
    descrambler #(.DATA_W(DATA_W)) descrambler_inst (
        .clk                     (clk),
        .rst_n                 (rst_n),
        .i_valid       (rx_data_valid),
        .i_scram_data     (gb_rx_data),
        .o_valid       (descram_valid),
        .o_descram_data (descram_data)
    );

    (* DONT_TOUCH = "TRUE" *)    
    decoder #(.DATA_W(DATA_W)) decoder_inst (
        .clk                      (clk),
        .rst_n                  (rst_n),
        .i_valid        (descram_valid),
        .i_data          (descram_data),
        .o_valid         (mac_rx_valid),
        .o_data           (mac_rx_data),
        .o_ctrl           (mac_rx_ctrl),
        .o_keep           (mac_rx_keep),
        .o_start         (mac_rx_start),
        .o_idle           (mac_rx_idle),
        .o_terminate (mac_rx_terminate),
        .o_error         (mac_rx_error)
    );

    assign block_lock = bs_lock;

endmodule