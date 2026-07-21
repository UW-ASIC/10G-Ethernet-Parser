`default_nettype none

module block_sync_rx #(

    parameter HEAD_W = 2
)(
    input  logic          clk,
    input  logic        rst_n,

    // from GTY SerDes (directly, same signal also goes to gearbox)
    +
    input  logic                i_serdes_v,   // serdes data is valid (CDR locked)

    // from gearbox
    input  logic                   i_valid,   // gearbox has a valid 66-bit block ready this cycle (flag to read header)
    input  logic [HEAD_W - 1 : 0]   i_head,   // 2-bit sync header to check

    // to gearbox
    output logic                    o_slip,   // tell gearbox to shift alignment by 1 bit

    // status
    output logic                    o_lock    // alignment found and confirmed
);

    // this module acts as a simple state machine, taking sync headers from the gearbox and evaluating alignment accuracy.
    
    /* once serdes data is valid (i_signal_ok from serdes) and gearbox has valid headers to share 
        (i_valid from gearbox_rx), start checking headers and counting:
        we expect to see valid headers (01 or 10) 64 times in a row.
        if at any point we see an invalid header (00 or 11), assert o_slip and reset. 
        
        This function brute forces an alignment search until we find the correct offset and lock. 
        We maintain lock until reset or signal loss. any further errors downstream (invalid block types, corrupted data) are handled by the decoder. */
  
    // * hint: header validation is a single XOR.


endmodule
