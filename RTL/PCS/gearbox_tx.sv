


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



    //  implement the sequence counter (0 to 32, reset on full)
    //  implement the buffer register for leftover bits
    // implement the barrel shifter/mask to assemble output from buffer + current block
    // *: o_accept = ~buffer_full

endmodule