//`default_nettype none

module encoder #(
    parameter DATA_W = 64
)(
    input  logic          clk,
    input  logic        rst_n,

    input  logic                      i_valid,
    input  logic [DATA_W - 1 : 0]      i_data,
    input  logic [DATA_W/8 - 1 : 0]    i_ctrl,
    input  logic [DATA_W/8 - 1 : 0]    i_keep,
    input  logic                      i_start,
    input  logic                       i_idle,
    input  logic                  i_terminate,
    input  logic                      i_error,

    output logic               o_valid,
    output logic [65 : 0]      o_data
);

    localparam CTRL_W = 7;

    localparam [7:0]
        BLOCK_TYPE_CTRL     = 8'h1e,
        BLOCK_TYPE_OS_4     = 8'h2d,
        BLOCK_TYPE_START_4  = 8'h33,
        BLOCK_TYPE_OS_04    = 8'h55,
        BLOCK_TYPE_OS_START = 8'h66,
        BLOCK_TYPE_START_0  = 8'h78,
        BLOCK_TYPE_OS_0     = 8'h4b,
        BLOCK_TYPE_TERM_0   = 8'h87,
        BLOCK_TYPE_TERM_1   = 8'h99,
        BLOCK_TYPE_TERM_2   = 8'haa,
        BLOCK_TYPE_TERM_3   = 8'hb4,
        BLOCK_TYPE_TERM_4   = 8'hcc,
        BLOCK_TYPE_TERM_5   = 8'hd2,
        BLOCK_TYPE_TERM_6   = 8'he1,
        BLOCK_TYPE_TERM_7   = 8'hff;

    localparam [CTRL_W-1:0] CTRL_IDLE  = 7'h00;
    localparam [CTRL_W-1:0] CTRL_ERROR = 7'h1e;

    // Format: o_data[1:0] = sync, o_data[9:2] = block type, o_data[65:10] = payload
    // Matches decoder's i_data layout exactly.

    logic [DATA_W/8-1:0] term_pos;

    always_comb begin
        o_valid  = i_valid;
        o_data   = '0;
        term_pos = i_keep + 8'd1;

        // default: idle control block
        o_data[1:0]   = 2'b10;
        o_data[9:2]   = BLOCK_TYPE_CTRL;
        o_data[65:10] = {8{CTRL_IDLE}};

        if (i_error) begin
            o_data[1:0]   = 2'b10;
            o_data[9:2]   = BLOCK_TYPE_CTRL;
            o_data[65:10] = {8{CTRL_ERROR}};
        end

        else if (i_ctrl == 8'h00) begin
            // pure data block
            o_data[1:0]   = 2'b01;
            o_data[65:2]  = i_data;
        end

        else if (i_idle) begin
            o_data[1:0]   = 2'b10;
            o_data[9:2]   = BLOCK_TYPE_CTRL;
            o_data[65:10] = {8{CTRL_IDLE}};
        end

        else if (i_start) begin
            // S0 D1 D2 D3 D4 D5 D6 D7
            o_data[1:0]   = 2'b10;
            o_data[9:2]   = BLOCK_TYPE_START_0;
            o_data[65:10] = i_data[63:8];
        end

        else if (i_terminate) begin
            o_data[1:0] = 2'b10;

            unique case (term_pos)
                8'b0000_0001: begin
                    // T0 C1 C2 C3 C4 C5 C6 C7
                    o_data[9:2]   = BLOCK_TYPE_TERM_0;
                    o_data[65:17] = {7{CTRL_IDLE}};
                end

                8'b0000_0010: begin
                    // D0 T1 C2 C3 C4 C5 C6 C7
                    o_data[9:2]   = BLOCK_TYPE_TERM_1;
                    o_data[17:10] = i_data[7:0];
                    o_data[65:24] = {6{CTRL_IDLE}};
                end

                8'b0000_0100: begin
                    // D0 D1 T2 C3 C4 C5 C6 C7
                    o_data[9:2]   = BLOCK_TYPE_TERM_2;
                    o_data[25:10] = i_data[15:0];
                    o_data[65:31] = {5{CTRL_IDLE}};
                end

                8'b0000_1000: begin
                    // D0 D1 D2 T3 C4 C5 C6 C7
                    o_data[9:2]   = BLOCK_TYPE_TERM_3;
                    o_data[33:10] = i_data[23:0];
                    o_data[65:38] = {4{CTRL_IDLE}};
                end

                8'b0001_0000: begin
                    // D0 D1 D2 D3 T4 C5 C6 C7
                    o_data[9:2]   = BLOCK_TYPE_TERM_4;
                    o_data[41:10] = i_data[31:0];
                    o_data[65:45] = {3{CTRL_IDLE}};
                end

                8'b0010_0000: begin
                    // D0 D1 D2 D3 D4 T5 C6 C7
                    o_data[9:2]   = BLOCK_TYPE_TERM_5;
                    o_data[49:10] = i_data[39:0];
                    o_data[65:52] = {2{CTRL_IDLE}};
                end

                8'b0100_0000: begin
                    // D0 D1 D2 D3 D4 D5 T6 C7
                    o_data[9:2]   = BLOCK_TYPE_TERM_6;
                    o_data[57:10] = i_data[47:0];
                    o_data[65:59] = CTRL_IDLE;
                end

                8'b1000_0000: begin
                    // D0 D1 D2 D3 D4 D5 D6 T7
                    o_data[9:2]   = BLOCK_TYPE_TERM_7;
                    o_data[65:10] = i_data[55:0];
                end

                default: begin
                    o_data[9:2]   = BLOCK_TYPE_CTRL;
                    o_data[65:10] = {8{CTRL_ERROR}};
                end
            endcase
        end
    end

endmodule