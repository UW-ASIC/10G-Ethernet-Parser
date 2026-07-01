// this module is purely combinational. clk/rst_n are included for optional output registering only.

module decoder #(

    parameter DATA_W = 64
)(
    input  logic          clk,
    input  logic        rst_n,

    // input from descrambler
    input  logic                      i_valid,       // block is valid from descrambler
    input  logic [DATA_W + 1 : 0]      i_data,        // 64 bit descrambled payload + 2 bit sync header

    // output to MAC 
    output logic                      o_valid,
    output logic [DATA_W - 1 : 0]      o_data,        // 8 bytes of XGMII data
    output logic [DATA_W/8 - 1 : 0]    o_ctrl,        // 8 flags of: 1 = control character, 0 = data character (per byte)
    output logic [DATA_W/8 - 1 : 0]    o_keep,        // 8 flags clarifying valid bytes in this beat (only meaningful on terminate blocks)
    output logic                      o_start,       // "this beat contains a Start character"
    output logic                       o_idle,        // "all 8 bytes are Idle"
    output logic                  o_terminate,   // "this beat contains a Terminate character"
    output logic                      o_error        // invalid sync header OR unrecognized block type
);

   
    localparam BLOCK_TYPE_W = 8;

    // block type codes from IEEE 802.3 clause 49 figure 49-7

    localparam [BLOCK_TYPE_W-1:0]
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

    // helper function to decode control codes
    function logic [7 : 0] decode_control_code (logic [6 : 0] control_code); 
        case (control_code) 
            7'h00: decode_control_code = 8'h07;     // idle
            7'h2d: decode_control_code = 8'h1c;     // reserved 0
            7'h33: decode_control_code = 8'h3c;     // reserved 1
            7'h4b: decode_control_code = 8'h7c;     // reserved 2
            7'h55: decode_control_code = 8'hbc;     // reserved 3
            7'h66: decode_control_code = 8'hdc;     // reserved 4
            7'h78: decode_control_code = 8'hf7;     // reserved 5
            default: decode_control_code = 8'hfe;   // error 
        endcase
    endfunction

    // helper function to decode o codes
    function logic [7 : 0] decode_o_code (logic [3 : 0] o_code); 
        case (o_code) 
            4'h0: decode_o_code = 8'h9c;            // Q
            4'hF: decode_o_code = 8'h5c;            // Fsig
            default: decode_o_code = 8'hfe;         // unrecognized, throw error 
        endcase
    endfunction

    // helper function to check error blocks 
    function logic is_error(logic [7 : 0] data); 
        return (data == 8'hfe); 
    endfunction

    always_comb begin
        // default values
        o_valid = i_valid; 
        o_data = '0;
        o_ctrl = 8'h00;
        o_keep = 8'h00;
        o_start = 1'b0;
        o_idle = 1'b0;
        o_terminate = 1'b0;
        o_error = 1'b0;

        if (i_valid) begin
            // invalid sync header
            if (i_data[0] == i_data[1]) begin
                o_error = 1'b1; 
            end

            // data blocks 
            else if (i_data[1 : 0] == 2'b01) begin 
                o_data = i_data[DATA_W + 1 : 2]; 
                o_keep = 8'hff;
            end

            // control blocks
            else begin 
                case (i_data[9 : 2])
                    BLOCK_TYPE_CTRL: begin
                        // C0 C1 C2 C3 / C4 C5 C6 C7 
                        o_data[7 : 0] = decode_control_code(i_data[16 : 10]); 
                        o_data[15 : 8] = decode_control_code(i_data[23 : 17]); 
                        o_data[23 : 16] = decode_control_code(i_data[30 : 24]); 
                        o_data[31 : 24] = decode_control_code(i_data[37 : 31]); 
                        o_data[39 : 32] = decode_control_code(i_data[44 : 38]); 
                        o_data[47 : 40] = decode_control_code(i_data[51 : 45]); 
                        o_data[55 : 48] = decode_control_code(i_data[58 : 52]); 
                        o_data[63 : 56] = decode_control_code(i_data[65 : 59]); 

                        // update flags 
                        o_ctrl = 8'hff; 
                        o_keep = 8'hff; 
                        if (o_data[63 : 0] == 64'h0707070707070707) begin 
                            o_idle = 1'b1; 
                        end 
                        // check error 
                        if (is_error(o_data[7:0]) || is_error(o_data[15:8]) || is_error(o_data[23:16]) || is_error(o_data[31:24]) ||
                            is_error(o_data[39:32]) || is_error(o_data[47:40]) || is_error(o_data[55:48]) || is_error(o_data[63:56])) begin 
                            o_error = 1'b1; 
                        end
                    end
                    
                    BLOCK_TYPE_OS_4: begin
                        // C0 C1 C2 C3 / O4 D5 D6 D7 
                        o_data[7 : 0] = decode_control_code(i_data[16 : 10]); 
                        o_data[15 : 8] = decode_control_code(i_data[23 : 17]); 
                        o_data[23 : 16] = decode_control_code(i_data[30 : 24]); 
                        o_data[31 : 24] = decode_control_code(i_data[37 : 31]); 
                        o_data[39 : 32] = decode_o_code(i_data[41 : 38]); 
                        o_data[63 : 40] = i_data[65 : 42]; 

                        // update flags 
                        o_ctrl = 8'h1f;         // 0001 1111
                        o_keep = 8'hff; 
                        // check error 
                        if (is_error(o_data[7:0]) || is_error(o_data[15:8]) || is_error(o_data[23:16]) || is_error(o_data[31:24]) || is_error(o_data[39:32])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_START_4: begin
                        // C0 C1 C2 C3 / S4 D5 D6 D7 
                        o_data[7 : 0] = decode_control_code(i_data[16 : 10]); 
                        o_data[15 : 8] = decode_control_code(i_data[23 : 17]); 
                        o_data[23 : 16] = decode_control_code(i_data[30 : 24]); 
                        o_data[31 : 24] = decode_control_code(i_data[37 : 31]); 
                        o_data[39 : 32] = 8'hfb; 
                        o_data[63 : 40] = i_data[65 : 42]; 

                        // update flags 
                        o_ctrl = 8'h1f;         // 0001 1111
                        o_keep = 8'hff; 
                        o_start = 1'b1; 
                        // check error 
                        if (is_error(o_data[7:0]) || is_error(o_data[15:8]) || is_error(o_data[23:16]) || is_error(o_data[31:24])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_OS_04: begin
                        // O0 D1 D2 D3 / S4 D5 D6 D7 
                        o_data[7 : 0] = decode_o_code(i_data[37 : 34]); 
                        o_data[31 : 8] = i_data[33 : 10]; 
                        o_data[39 : 32] = 8'hfb; 
                        o_data[63 : 40] = i_data[65 : 42]; 

                        // update flags 
                        o_ctrl = 8'h11;         // 0001 0001
                        o_keep = 8'hff; 
                        o_start = 1'b1; 
                        // check error 
                        if (is_error(o_data[7:0])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_OS_START: begin
                        // O0 D1 D2 D3 / O4 D5 D6 D7 
                        o_data[7 : 0] = decode_o_code(i_data[37 : 34]); 
                        o_data[31 : 8] = i_data[33 : 10]; 
                        o_data[39 : 32] = decode_o_code(i_data[41 : 38]); 
                        o_data[63 : 40] = i_data[65 : 42]; 

                        // update flags 
                        o_ctrl = 8'h11;         // 0001 0001 
                        o_keep = 8'hff; 
                        o_start = 1'b1;
                        // check error 
                        if (is_error(o_data[7:0]) || is_error(o_data[39:32])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_START_0: begin
                        // S0 D1 D2 D3 / D4 D5 D6 D7 
                        o_data[7 : 0] = 8'hfb;
                        o_data[63 : 8] = i_data[65 : 10]; 

                        // update flags 
                        o_ctrl = 8'h01;         // 0000 0001
                        o_keep = 8'hff; 
                        o_start = 1'b1; 
                    end

                    BLOCK_TYPE_OS_0: begin
                        // O0 D1 D2 D3 / C4 C5 C6 C7 
                        o_data[7 : 0] = decode_o_code(i_data[37 : 34]);
                        o_data[31 : 8] = i_data[33 : 10]; 
                        o_data[39 : 32] = decode_control_code(i_data[44 : 38]); 
                        o_data[47 : 40] = decode_control_code(i_data[51 : 45]); 
                        o_data[55 : 48] = decode_control_code(i_data[58 : 52]); 
                        o_data[63 : 56] = decode_control_code(i_data[65 : 59]);

                        // update flags 
                        o_ctrl = 8'hf1;         // 1111 0001
                        o_keep = 8'hff; 
                        // check error 
                        if (is_error(o_data[7:0]) || is_error(o_data[39:32]) || is_error(o_data[47:40]) || is_error(o_data[55:48]) || is_error(o_data[63:56])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_TERM_0: begin
                        // T0 C1 C2 C3 / C4 C5 C6 C7 
                        o_data[7 : 0] = 8'hfd; 
                        o_data[15 : 8] = decode_control_code(i_data[23 : 17]); 
                        o_data[23 : 16] = decode_control_code(i_data[30 : 24]); 
                        o_data[31 : 24] = decode_control_code(i_data[37 : 31]); 
                        o_data[39 : 32] = decode_control_code(i_data[44 : 38]); 
                        o_data[47 : 40] = decode_control_code(i_data[51 : 45]); 
                        o_data[55 : 48] = decode_control_code(i_data[58 : 52]); 
                        o_data[63 : 56] = decode_control_code(i_data[65 : 59]); 

                        // update flags 
                        o_ctrl = 8'hff;         // 1111 1111
                        o_keep = 8'h01;         // 0000 0001
                        o_terminate = 1'b1; 
                        // check error 
                        if (is_error(o_data[15:8]) || is_error(o_data[23:16]) || is_error(o_data[31:24]) || is_error(o_data[39:32]) || is_error(o_data[47:40]) || is_error(o_data[55:48]) || is_error(o_data[63:56])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_TERM_1: begin
                        // D0 T1 C2 C3 / C4 C5 C6 C7 
                        o_data[7 : 0] = i_data[17 : 10]; 
                        o_data[15 : 8] = 8'hfd; 
                        o_data[23 : 16] = decode_control_code(i_data[30 : 24]); 
                        o_data[31 : 24] = decode_control_code(i_data[37 : 31]); 
                        o_data[39 : 32] = decode_control_code(i_data[44 : 38]); 
                        o_data[47 : 40] = decode_control_code(i_data[51 : 45]); 
                        o_data[55 : 48] = decode_control_code(i_data[58 : 52]); 
                        o_data[63 : 56] = decode_control_code(i_data[65 : 59]); 

                        // update flags 
                        o_ctrl = 8'hfe;         // 1111 1110
                        o_keep = 8'h03;         // 0000 0011
                        o_terminate = 1'b1; 
                        // check error 
                        if (is_error(o_data[23:16]) || is_error(o_data[31:24]) || is_error(o_data[39:32]) || is_error(o_data[47:40]) || is_error(o_data[55:48]) || is_error(o_data[63:56])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_TERM_2: begin
                        // D0 D1 T2 C3 / C4 C5 C6 C7 
                        o_data[15 : 0] = i_data[25 : 10]; 
                        o_data[23 : 16] = 8'hfd; 
                        o_data[31 : 24] = decode_control_code(i_data[37 : 31]); 
                        o_data[39 : 32] = decode_control_code(i_data[44 : 38]); 
                        o_data[47 : 40] = decode_control_code(i_data[51 : 45]); 
                        o_data[55 : 48] = decode_control_code(i_data[58 : 52]); 
                        o_data[63 : 56] = decode_control_code(i_data[65 : 59]); 

                        // update flags 
                        o_ctrl = 8'hfc;         // 1111 1100
                        o_keep = 8'h07;         // 0000 0111
                        o_terminate = 1'b1; 
                        // check error 
                        if (is_error(o_data[31:24]) || is_error(o_data[39:32]) || is_error(o_data[47:40]) || is_error(o_data[55:48]) || is_error(o_data[63:56])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_TERM_3: begin
                        // D0 D1 D2 T3 / C4 C5 C6 C7 
                        o_data[23 : 0] = i_data[33 : 10]; 
                        o_data[31 : 24] = 8'hfd; 
                        o_data[39 : 32] = decode_control_code(i_data[44 : 38]); 
                        o_data[47 : 40] = decode_control_code(i_data[51 : 45]); 
                        o_data[55 : 48] = decode_control_code(i_data[58 : 52]); 
                        o_data[63 : 56] = decode_control_code(i_data[65 : 59]); 

                        // update flags 
                        o_ctrl = 8'hf8;         // 1111 1000
                        o_keep = 8'h0f;         // 0000 1111
                        o_terminate = 1'b1; 
                        // check error 
                        if (is_error(o_data[39:32]) || is_error(o_data[47:40]) || is_error(o_data[55:48]) || is_error(o_data[63:56])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_TERM_4: begin
                        // D0 D1 D2 D3 / T4 C5 C6 C7 
                        o_data[31 : 0] = i_data[41 : 10]; 
                        o_data[39 : 32] = 8'hfd; 
                        o_data[47 : 40] = decode_control_code(i_data[51 : 45]); 
                        o_data[55 : 48] = decode_control_code(i_data[58 : 52]); 
                        o_data[63 : 56] = decode_control_code(i_data[65 : 59]); 

                        // update flags 
                        o_ctrl = 8'hf0;         // 1111 0000
                        o_keep = 8'h1f;         // 0001 1111
                        o_terminate = 1'b1; 
                        // check error 
                        if (is_error(o_data[47:40]) || is_error(o_data[55:48]) || is_error(o_data[63:56])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_TERM_5: begin
                        // D0 D1 D2 D3 / D4 T5 C6 C7 
                        o_data[39 : 0] = i_data[49 : 10]; 
                        o_data[47 : 40] = 8'hfd; 
                        o_data[55 : 48] = decode_control_code(i_data[58 : 52]); 
                        o_data[63 : 56] = decode_control_code(i_data[65 : 59]); 

                        // update flags 
                        o_ctrl = 8'he0;         // 1110 0000
                        o_keep = 8'h3f;         // 0011 1111
                        o_terminate = 1'b1; 
                        // check error 
                        if (is_error(o_data[55:48]) || is_error(o_data[63:56])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_TERM_6: begin
                        // D0 D1 D2 D3 / D4 D5 T6 C7 
                        o_data[47 : 0] = i_data[57 : 10]; 
                        o_data[55 : 48] = 8'hfd; 
                        o_data[63 : 56] = decode_control_code(i_data[65 : 59]); 

                        // update flags 
                        o_ctrl = 8'hc0;         // 1100 0000
                        o_keep = 8'h7f;         // 0111 1111
                        o_terminate = 1'b1; 
                        // check error 
                        if (is_error(o_data[63:56])) begin 
                            o_error = 1'b1; 
                        end
                    end

                    BLOCK_TYPE_TERM_7: begin
                        // D0 D1 D2 D3 / D4 D5 D6 T7 
                        o_data[55 : 0] = i_data[65 : 10]; 
                        o_data[63 : 56] = 8'hfd; 

                        // update flags 
                        o_ctrl = 8'h80;         // 1000 0000
                        o_keep = 8'hff;         // 1111 1111
                        o_terminate = 1'b1; 
                    end

                    default: begin 
                        // undefined type, throw error
                        o_error = 1'b1; 
                        o_ctrl = 8'hFF; 
                    end
                endcase
            end
        end
    end    

endmodule
