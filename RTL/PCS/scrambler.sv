`timescale 1ns / 1ps

module scrambler #(

    parameter DATA_W = 64
)(
    input  logic          clk,
    input  logic        rst_n,

 
    // input from encoder
    input  logic                       i_valid,  // block is valid from encoder
    input  logic [DATA_W + 1 : 0]   i_enc_data,  // 64 bit of unscrambled data + 2 unchanged sync header bits: received from encoder
   
 
    // output to gearbox_tx
    output logic                       o_valid,
    output logic [DATA_W + 1 : 0] o_scram_data   // 64 bit of scrambled data + 2 unchanged sync header bits: sent to gearbox_tx
   
);
 
    // scrambling polynomial: x^58 + x^39 + 1;

    localparam I0 = 58;
    localparam I1 = 39;


    //------
    // *: Some key differences from the scrambler: 

    //       descrambler state tracks INPUT (scrambled data received)
    //       scrambler state tracks OUTPUT (scrambled data produced)
    //       this creates a dependency chain: each output bit depends on earlier output bits-
    //       -from the same cycle, not just input bits.
    //------

    // Each OUT bit is a fixed XOR of specific input and output bits, plus state bits:
    //   (state is stored in reversed order: state[i] = last_OUTPUT[63-i])

    // - bits  0 to 38:  both taps land in previous state
    //   OUT[i] = data[i] XOR state[38-i] XOR state[57-i]
   
    // - bits 39 to 57:  one tap lands in current OUTPUT, one in previous state
    //   OUT[i] = data[i] XOR OUT[i-39] XOR state[57-i]
   
    // - bits 58 to 63:  both taps land in current OUTPUT
    //   OUT[i] = data[i] XOR OUT[i-39] XOR OUT[i-58]


    logic [57:0] state, state_next;
    // implement the parallel XOR equations (3 ranges for x <= I1,  I1 < x <= I0, I0 < x, as described above)
    integer j;
    always_ff @(posedge clk) begin
        if (~rst_n) begin
            state <= '0;
            o_valid <= '0;
        end else begin
            if (i_valid) begin
                for (j=0; j < 64; j++) begin
                    state[j] <= o_scram_data[63-j];
                end
                o_valid <= 1'b1;
            end else begin
                o_valid <= 1'b0;
            end
        end
    end
    genvar i;
    generate
        for (i=0; i < 64; i++) begin
            if (i < I1) begin
                assign o_scram_data[i] = i_enc_data[i] ^ state[38-i] ^ state[57-i];
            end else if (i < I0) begin
                assign o_scram_data[i] = i_enc_data[i] ^ o_scram_data[i-39] ^ state[57-i];
            end else begin
                assign o_scram_data[i] = i_enc_data[i] ^ o_scram_data[i-39] ^ o_scram_data[i-58];
            end
        end
    endgenerate
    assign o_scram_data[65:64] = i_enc_data[65:64];
//     *: state_next stores last 58 bits of OUTPUT (not input) in reversed order: state_next[i] = OUT[63-i]
//     *: update state with state_next on each valid cycle
//     *: pass sync_header through unchanged
 
endmodule