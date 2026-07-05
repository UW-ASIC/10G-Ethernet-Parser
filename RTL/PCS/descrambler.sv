

module descrambler #(

    parameter DATA_W = 64
)(
    input  logic          clk,
    input  logic        rst_n,

 
    // input from gearbox (after block sync confirms alignment)
    input  logic                         i_valid,  // block is valid and aligned from gearbox
    input  logic [DATA_W + 1 : 0]   i_scram_data,  // 64 bit of scrambled data + 2 unchanged sync header bits: received from gearbox
   
 
    // ouput to decoder
    output logic                         o_valid,
    output logic [DATA_W + 1 : 0] o_descram_data   // 64 bit of descrambled data + 2 unchanged sync header bits: sent to decoder
   
);
 
    // scrambling polynomial: x^58 + x ^ 39 + 1;

    localparam I0 = 58;
    localparam I1 = 39;

    // Each OUT bit is a fixed XOR of specific input bits and state bits:
    //   (state is stored in reversed order: state[i] = last_input[63-i])

    // - bits  0 to 38:  both taps land in previous state
    //   OUT[i] = data[i] XOR state[38-i] XOR state[57-i]
   
    // - bits 39 to 57:  one tap lands in current input, one in previous state
    //   OUT[i] = data[i] XOR data[i-39] XOR state[57-i]
   
    // - bits 58 to 63:  both taps land in current input
    //   OUT[i] = data[i] XOR data[i-39] XOR data[i-58]


    logic [57:0] state, state_next;
    // implement the parallel XOR equations (3 ranges for x <= I1,  I1 < x <= I0, I0 < x, as described above)

    // *: update state_q with state_next on each valid cycle
    // *: pass sync_header through unchanged
 
endmodule
