`timescale 1ns / 1ps

module scrambler #(
    parameter DATA_W = 64
)(
    input logic clk,
    input logic rst_n,

    // input from encoder
    input logic i_valid,                         // block is valid from encoder
    input logic [DATA_W + 1 : 0] i_enc_data,    // 2 unchanged sync header bits + 64 bit of unscrambled data: received from encoder

    // output to gearbox_tx
    output logic o_valid,
    output logic [DATA_W + 1 : 0] o_scram_data  // 2 unchanged sync header bits + 64 bit of scrambled data: sent to gearbox_tx
);

    // scrambling polynomial: x^58 + x^39 + 1;
    localparam I0 = 58;
    localparam I1 = 39;

    //------
    // *: Some key differences from the scrambler:
    // descrambler state tracks INPUT (scrambled data received)
    // scrambler state tracks OUTPUT (scrambled data produced)
    // this creates a dependency chain: each output bit depends on earlier output bits-
    // -from the same cycle, not just input bits.
    //------

    // Each OUT bit is a fixed XOR of specific input and output bits, plus state bits:
    // (state is stored in reversed order: state[i] = last_OUTPUT[65-i])
    // - bits 2 to 40: both taps land in previous state
    // OUT[i+2] = data[i+2] XOR state[38-i] XOR state[57-i]
    // - bits 41 to 59: one tap lands in current OUTPUT, one in previous state
    // OUT[i+2] = data[i+2] XOR OUT[i-39+2] XOR state[57-i]
    // - bits 60 to 65: both taps land in current OUTPUT
    // OUT[i+2] = data[i+2] XOR OUT[i-39+2] XOR OUT[i-58+2]

    logic [57:0] state;

    // implement the parallel XOR equations (3 ranges for x <= I1, I1 < x <= I0, I0 < x, as described above)
    integer j;
    always_ff @(posedge clk) begin
        if (~rst_n) begin
            state <= {58{1'b1}};
        end
        else begin
            if (i_valid) begin
                for (j=0; j < 58; j++) begin
                    state[j] <= o_scram_data[65-j];
                end
            end
            else begin
                state <= state;
            end
        end
    end

    genvar i;
    generate
        for (i=0; i < 64; i++) begin
            if (i < I1) begin
                assign o_scram_data[i+2] =
                    i_enc_data[i+2] ^
                    state[38-i] ^
                    state[57-i];
            end
            else if (i < I0) begin
                assign o_scram_data[i+2] =
                    i_enc_data[i+2] ^
                    o_scram_data[i-39+2] ^
                    state[57-i];
            end
            else begin
                assign o_scram_data[i+2] =
                    i_enc_data[i+2] ^
                    o_scram_data[i-39+2] ^
                    o_scram_data[i-58+2];
            end
        end
    endgenerate

    assign o_valid = i_valid;
    assign o_scram_data[1:0] = i_enc_data[1:0];

    // *: state_next stores last 58 bits of OUTPUT (not input) in reversed order: state_next[i] = OUT[65-i]
    // *: update state with state_next on each valid cycle
    // *: pass sync_header through unchanged

endmodule
