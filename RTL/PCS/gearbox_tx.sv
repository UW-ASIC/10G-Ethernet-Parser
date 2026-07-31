


module gearbox_tx #(

    parameter DATA_W = 64,
    parameter HEAD_W = 2
)(
    input  logic          clk,
    input  logic        rst_n,

    // input from scrambler
    input  logic [HEAD_W - 1 : 0]           i_head,   // 2-bit sync header from encoder
    input  logic [DATA_W - 1 : 0]           i_data,   // 64-bit scrambled payload

    // to GTY SerDes
    output logic [DATA_W - 1 : 0]           o_data,   // 64 bits to SerDes every cycle

    // backpressure to scrambler/encoder
    output logic                          o_accept    // when low, buffer is full, tell scrambler not to send the next stream. 
);

    localparam BLOCK_W = DATA_W + HEAD_W;  // 66

    // this module handles the reverse problem of gearbox_rx: packing 66-bit blocks into a 64-bit bus
    // no slip, no block sync, no alignment search. we're generating the stream, so we know exactly where every block goes and thus it's much simpler.

    
    // sequence counter:
    //   counts from 0 to 32. increments by 1 each cycle.
    //   at each count, the buffer holds (seq * 2) leftover bits from previous blocks.
    //   when seq hits 32 (buffer holds 64 bits = full), reset to 0 and deassert o_accept for one cycle so upstream stops sending.
    //
    // buffer register (64 bits):
    //   stores the leftover bits that didn't fit into the previous output word.
    //   each cycle, the output is assembled from:
    //     - lower bits from buffer (previous leftovers)
    //     - upper bits from current block ({data, head} shifted into position)
    //   leftover bits from the current block get written back into the buffer
    //   for next cycle.
    //
    // output assembly: same barrel shifter concept as gearbox_rx but in reverse (Read the gearbox_rx comments).
    //   a mask derived from the sequence counter selects which bits of the output
    //   come from the buffer vs the current block.
    //
    // o_accept:
    //   high normally. goes low for one cycle when the buffer is full (seq = 32).
    //   upstream (scrambler/encoder) must hold its data when o_accept is low


    // sequence counter: 0 to 32, leftover_count = seq * 2
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

    // 66-bit block: {data[63:0], head[1:0]}, head in LSBs (transmitted first)
    wire [BLOCK_W - 1 : 0] block = {i_data, i_head};

    logic [DATA_W - 1 : 0] buf_r;

    // combined bus: current block above buffered leftovers [129:0]
    wire [BLOCK_W + DATA_W - 1 : 0] combined = {block, buf_r};

    logic [DATA_W - 1 : 0] out_word;
    logic [DATA_W - 1 : 0] next_leftover;

    // barrel-shifter mux: select 64 output bits and remaining leftover from combined
    always_comb begin
        if (buffer_full) begin
            out_word      = buf_r;
            next_leftover = '0;
        end else begin
            case (seq)
                6'd0:  begin out_word = combined[127 : 64]; next_leftover = {block[65:64], 62'b0}; end
                6'd1:  begin out_word = combined[125 : 62]; next_leftover = {block[65:62], 60'b0}; end
                6'd2:  begin out_word = combined[123 : 60]; next_leftover = {block[65:60], 58'b0}; end
                6'd3:  begin out_word = combined[121 : 58]; next_leftover = {block[65:58], 56'b0}; end
                6'd4:  begin out_word = combined[119 : 56]; next_leftover = {block[65:56], 54'b0}; end
                6'd5:  begin out_word = combined[117 : 54]; next_leftover = {block[65:54], 52'b0}; end
                6'd6:  begin out_word = combined[115 : 52]; next_leftover = {block[65:52], 50'b0}; end
                6'd7:  begin out_word = combined[113 : 50]; next_leftover = {block[65:50], 48'b0}; end
                6'd8:  begin out_word = combined[111 : 48]; next_leftover = {block[65:48], 46'b0}; end
                6'd9:  begin out_word = combined[109 : 46]; next_leftover = {block[65:46], 44'b0}; end
                6'd10: begin out_word = combined[107 : 44]; next_leftover = {block[65:44], 42'b0}; end
                6'd11: begin out_word = combined[105 : 42]; next_leftover = {block[65:42], 40'b0}; end
                6'd12: begin out_word = combined[103 : 40]; next_leftover = {block[65:40], 38'b0}; end
                6'd13: begin out_word = combined[101 : 38]; next_leftover = {block[65:38], 36'b0}; end
                6'd14: begin out_word = combined[99  : 36]; next_leftover = {block[65:36], 34'b0}; end
                6'd15: begin out_word = combined[97  : 34]; next_leftover = {block[65:34], 32'b0}; end
                6'd16: begin out_word = combined[95  : 32]; next_leftover = {block[65:32], 30'b0}; end
                6'd17: begin out_word = combined[93  : 30]; next_leftover = {block[65:30], 28'b0}; end
                6'd18: begin out_word = combined[91  : 28]; next_leftover = {block[65:28], 26'b0}; end
                6'd19: begin out_word = combined[89  : 26]; next_leftover = {block[65:26], 24'b0}; end
                6'd20: begin out_word = combined[87  : 24]; next_leftover = {block[65:24], 22'b0}; end
                6'd21: begin out_word = combined[85  : 22]; next_leftover = {block[65:22], 20'b0}; end
                6'd22: begin out_word = combined[83  : 20]; next_leftover = {block[65:20], 18'b0}; end
                6'd23: begin out_word = combined[81  : 18]; next_leftover = {block[65:18], 16'b0}; end
                6'd24: begin out_word = combined[79  : 16]; next_leftover = {block[65:16], 14'b0}; end
                6'd25: begin out_word = combined[77  : 14]; next_leftover = {block[65:14], 12'b0}; end
                6'd26: begin out_word = combined[75  : 12]; next_leftover = {block[65:12], 10'b0}; end
                6'd27: begin out_word = combined[73  : 10]; next_leftover = {block[65:10], 8'b0}; end
                6'd28: begin out_word = combined[71  :  8]; next_leftover = {block[65:8],  6'b0}; end
                6'd29: begin out_word = combined[69  :  6]; next_leftover = {block[65:6],  4'b0}; end
                6'd30: begin out_word = combined[67  :  4]; next_leftover = {block[65:4],  2'b0}; end
                6'd31: begin out_word = combined[65  :  2]; next_leftover = block[65:2];            end
                default: begin out_word = buf_r; next_leftover = '0; end
            endcase
        end
    end

    // buffer register: stores leftover bits for the next cycle
    always_ff @(posedge clk) begin
        if (~rst_n)
            buf_r <= '0;
        else if (buffer_full)
            buf_r <= '0;
        else
            buf_r <= next_leftover;
    end

    // output register
    always_ff @(posedge clk) begin
        if (~rst_n)
            o_data <= '0;
        else
            o_data <= out_word;
    end

endmodule