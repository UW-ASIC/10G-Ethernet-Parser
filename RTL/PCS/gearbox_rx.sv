
module gearbox_rx #(

    parameter DATA_W = 64,
    parameter HEAD_W = 2
)(
    input  logic          clk,
    input  logic        rst_n,

    // input from GTY SerDes
    input  logic [DATA_W - 1 : 0]           i_data,   // 64 bits of raw parallel data, arrives every cycle when pma_lock is high
    input  logic                        i_pma_lock,   // GTY CDR is locked, i_data is real. reset pointer when low.

    // from block sync
    input  logic                            i_slip,   // shift extraction point by 1 extra bit

    // to descrambler
    output logic [DATA_W + HEAD_W - 1 : 0]  o_data,   // 66-bit aligned block: {payload[63:0], sync_header[1:0]}

    // to block sync
    output logic                           o_valid,   // 66-bit block is ready (sent out to block_sync and downstream modules)
    output logic [HEAD_W - 1 : 0]           o_head    // 2-bit sync header for block sync to validate
);

    localparam BLOCK_W = DATA_W + HEAD_W;  // 66 bits in total

    /* this component utilizes an architecture called a barrel shifter. while shift registers can provide single bit shifts,
         we need to support arbitrary shift amounts to extract 66-bit blocks from a continuously drifting offset within the 64-bit input bus. 
         the offset changes every cycle (drift of 2 bits) and can shift by an extra bit on slip.
         a barrel shifter lets us select any 66-bit window from a wide buffer
         in a single cycle, without needing to shift one bit at a time.
         on an FPGA, wide barrel shifters are expensive in LUTs if implemented
         naively. We will switch to directly using hardened fpga primitives (SRLC32E, MUXF9, MUXF8. MUXF7, etc.) to keep this efficient at 156.25 MHz.
     */

    
    // input buffer: concatenation of previous cycle's i_data (stored in a register)
    //   with current cycle's i_data, giving us 128 bits to select from.
    //   the sequence counter is the barrel shifter's select signal, pointing
    //   to where the current 66-bit block starts within that 128-bit window.
    //
    // sequence counter:
    //   advances by 2 each cycle (66 - 64 = 2 bit drift per block)
    //   advances by 3 on i_slip (1 extra bit for realignment)
    //   wraps at 64. resets to 0 when i_pma_lock drops.
    //
    // valid:
    //   when seq counter is 0 or 1, the 66-bit window can't be fully formed
    //   from available data. o_valid goes low. only module in PCS that skips cycles.

    // implement the 128-bit buffer (concatenation of stored and current i_data)
    // implement the barrel shifter to extract 66 bits at the offset given by seq counter, utilize macros as much as possible. 
    // implement the sequence counter with slip and pma_lock handling
    // *: o_head is the bottom 2 bits of the barrel shifter output, sent out to block_sync for alignment correction. 


endmodule