

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

    logic [57:0] state; //stores the last 58 bits, 0 being most recent.
    logic [DATA_W-1:0] descrambled; //descrambled data
    logic [DATA_W+1:0] total_descram; //descrambled data + header
    always_comb begin
        //for bits 0 to 38
        for(int i = 0; i<= 38; i++) begin
            descrambled[i] = i_scram_data[i] 
            ^state[38-i] 
            ^state[57-i]; 
        end
        //for bits 39 to 57
        for(int i = 39; i<=57; i++) begin
            descrambled[i] = i_scram_data[i]
            ^i_scram_data[i-39] //
            ^state[57-i];
        end
        //for bits 58 to 63
        for(int i = 58; i <= 63; i++) begin
            descrambled[i] = i_scram_data[i]
            ^i_scram_data[i-39]
            ^i_scram_data[i-58];
        end
    end
    // *: update state with state_next on each valid cycle
    always @(posedge clk) begin
        //if(!rst_n)
        if(!rst_n) begin
            state <= '1; 
            o_valid <= 0;
            total_descram<= 0;
        end else begin
            o_valid <= i_valid;
             if(i_valid) begin
                //Store state (current input scram) in reverse order
                for(int i = 0; i< 58; i++) begin
                    state[i] <= i_scram_data[63-i];
                end
                //Header + descrambled
                total_descram <= {i_scram_data[65:64], descrambled};
            end
        end

        
    end
    assign o_descram_data = total_descram;
 
endmodule
