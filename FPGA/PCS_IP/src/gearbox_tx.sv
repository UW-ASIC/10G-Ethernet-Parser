module gearbox_tx #(
    parameter DATA_W = 64,
    parameter HEAD_W = 2
)(
    input  logic          clk,
    input  logic        rst_n,

    input  logic [HEAD_W - 1 : 0]           i_head,
    input  logic [DATA_W - 1 : 0]           i_data,

    output logic [DATA_W - 1 : 0]           o_data,
    output logic                          o_accept
);

    localparam BLOCK_W = DATA_W + HEAD_W;

    // sequence counter: 0 to 32
    logic [5:0] seq;
    wire buffer_full = (seq == 6'd32);

    always_ff @(posedge clk) begin
        if (~rst_n)
            seq <= 6'd0;
        else if (buffer_full)
            seq <= 6'd0;
        else
            seq <= seq + 6'd1;
    end

    assign o_accept = ~buffer_full;

    // block: header in LSBs, matching RX assembled layout
    wire [BLOCK_W - 1 : 0] block = {i_data, i_head};

    logic [DATA_W - 1 : 0] buf_r;

    // output and leftover computation
    // RX extracts: assembled = {barrel[63-2N:0], i_data[63:62-2N]}
    //   => leftover must sit in MSBs of the next output word
    //
    // at seq N: output = {buf_r_top_2N_bits, block_top_(64-2N)_bits}
    //           leftover = block_bottom_(2N+2)_bits, stored in MSBs of buf_r

    logic [DATA_W - 1 : 0] out_word;
    logic [DATA_W - 1 : 0] next_leftover;

    always_comb begin
        if (buffer_full) begin
            out_word      = buf_r;
            next_leftover = '0;
        end else begin
            case (seq)
                6'd0:  begin out_word = block[65:2];                           next_leftover = {block[1:0],   62'b0}; end
                6'd1:  begin out_word = {buf_r[63:62], block[65:4]};           next_leftover = {block[3:0],   60'b0}; end
                6'd2:  begin out_word = {buf_r[63:60], block[65:6]};           next_leftover = {block[5:0],   58'b0}; end
                6'd3:  begin out_word = {buf_r[63:58], block[65:8]};           next_leftover = {block[7:0],   56'b0}; end
                6'd4:  begin out_word = {buf_r[63:56], block[65:10]};          next_leftover = {block[9:0],   54'b0}; end
                6'd5:  begin out_word = {buf_r[63:54], block[65:12]};          next_leftover = {block[11:0],  52'b0}; end
                6'd6:  begin out_word = {buf_r[63:52], block[65:14]};          next_leftover = {block[13:0],  50'b0}; end
                6'd7:  begin out_word = {buf_r[63:50], block[65:16]};          next_leftover = {block[15:0],  48'b0}; end
                6'd8:  begin out_word = {buf_r[63:48], block[65:18]};          next_leftover = {block[17:0],  46'b0}; end
                6'd9:  begin out_word = {buf_r[63:46], block[65:20]};          next_leftover = {block[19:0],  44'b0}; end
                6'd10: begin out_word = {buf_r[63:44], block[65:22]};          next_leftover = {block[21:0],  42'b0}; end
                6'd11: begin out_word = {buf_r[63:42], block[65:24]};          next_leftover = {block[23:0],  40'b0}; end
                6'd12: begin out_word = {buf_r[63:40], block[65:26]};          next_leftover = {block[25:0],  38'b0}; end
                6'd13: begin out_word = {buf_r[63:38], block[65:28]};          next_leftover = {block[27:0],  36'b0}; end
                6'd14: begin out_word = {buf_r[63:36], block[65:30]};          next_leftover = {block[29:0],  34'b0}; end
                6'd15: begin out_word = {buf_r[63:34], block[65:32]};          next_leftover = {block[31:0],  32'b0}; end
                6'd16: begin out_word = {buf_r[63:32], block[65:34]};          next_leftover = {block[33:0],  30'b0}; end
                6'd17: begin out_word = {buf_r[63:30], block[65:36]};          next_leftover = {block[35:0],  28'b0}; end
                6'd18: begin out_word = {buf_r[63:28], block[65:38]};          next_leftover = {block[37:0],  26'b0}; end
                6'd19: begin out_word = {buf_r[63:26], block[65:40]};          next_leftover = {block[39:0],  24'b0}; end
                6'd20: begin out_word = {buf_r[63:24], block[65:42]};          next_leftover = {block[41:0],  22'b0}; end
                6'd21: begin out_word = {buf_r[63:22], block[65:44]};          next_leftover = {block[43:0],  20'b0}; end
                6'd22: begin out_word = {buf_r[63:20], block[65:46]};          next_leftover = {block[45:0],  18'b0}; end
                6'd23: begin out_word = {buf_r[63:18], block[65:48]};          next_leftover = {block[47:0],  16'b0}; end
                6'd24: begin out_word = {buf_r[63:16], block[65:50]};          next_leftover = {block[49:0],  14'b0}; end
                6'd25: begin out_word = {buf_r[63:14], block[65:52]};          next_leftover = {block[51:0],  12'b0}; end
                6'd26: begin out_word = {buf_r[63:12], block[65:54]};          next_leftover = {block[53:0],  10'b0}; end
                6'd27: begin out_word = {buf_r[63:10], block[65:56]};          next_leftover = {block[55:0],   8'b0}; end
                6'd28: begin out_word = {buf_r[63:8],  block[65:58]};          next_leftover = {block[57:0],   6'b0}; end
                6'd29: begin out_word = {buf_r[63:6],  block[65:60]};          next_leftover = {block[59:0],   4'b0}; end
                6'd30: begin out_word = {buf_r[63:4],  block[65:62]};          next_leftover = {block[61:0],   2'b0}; end
                6'd31: begin out_word = {buf_r[63:2],  block[65:64]};          next_leftover = block[63:0];           end
                default: begin out_word = buf_r; next_leftover = '0; end
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (~rst_n)
            buf_r <= '0;
        else if (buffer_full)
            buf_r <= '0;
        else
            buf_r <= next_leftover;
    end

    always_ff @(posedge clk) begin
        if (~rst_n)
            o_data <= '0;
        else
            o_data <= out_word;
    end

endmodule