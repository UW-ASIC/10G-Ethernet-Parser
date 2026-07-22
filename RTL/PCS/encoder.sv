`default_nettype none
// this module is purely combinational. clk/rst_n are included for optional output registering only.

module encoder #(

    parameter DATA_W = 64
)
(
    input  logic          clk,
    input  logic        rst_n,

    // input from MAC TX 
    input  logic                      i_valid,
    input  logic [DATA_W - 1 : 0]      i_data,       // 8 bytes of data
    input  logic [DATA_W/8 - 1 : 0]    i_ctrl,       // 8 flags: 1 = control character, 0 = data character (per byte)
    input  logic [DATA_W/8 - 1 : 0]    i_keep,       // valid bytes in this beat
    input  logic                      i_start,       // this beat contains a Start character
    input  logic                       i_idle,       // all 8 bytes are Idle
    input  logic                  i_terminate,       // this beat contains a Terminate character
    input  logic                      i_error,       // error indication

    // output to scrambler
    output logic               o_valid,
    output logic [65 : 0]      o_data         // 64 bit encoded payload + 2 bit sync header: sent to scrambler
);

  
    localparam CTRL_W = 7;

    // block type codes from IEEE 802.3 clause 49 figure 49-7
    localparam [7:0]
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

    // idle control code: XGMII Idle (0x07) maps to 7-bit C code 0x00
    localparam [CTRL_W-1:0] CTRL_IDLE = 7'h00;

    // header:
    //   if all i_ctrl bits are 0: this is a data block, sync = 2'b01
    //   if any i_ctrl bit is 1:  this is a control block, sync = 2'b10
    

    // data blocks (sync = 01):
    //   payload = i_data as-is. no block type field needed, so you may pass it through directly

    // control blocks (sync = 10):
    //   determine which block type to use based on i_start, i_terminate, i_idle:
    //
    //   i_idle:       block type = 0x1E. fill payload with 8 x CTRL_IDLE (7-bit each).
    //   i_start:      block type = 0x78. payload = block type + 7 data bytes after Start.
    //   i_terminate:  block type depends on WHERE terminate falls (how many valid data bytes).
    //   use i_keep to determine the terminate position.

    // * hint: if you add 1 to i_keep, the result is a one-hot code indicating terminate position.
    //   You can use a case statement on that one-hot value to select the correct BLOCK_TYPE_TERM_x (:
  
    

    // payload for control blocks:
    //   the lower 8 bits of the 64-bit payload = block type field
    //   the upper 56 bits = data bytes and/or control codes arranged per documentation chart
    //   for idle blocks: upper 56 bits = 8 x 7-bit CTRL_IDLE codes
    //   for terminate blocks: data bytes in lower positions, CTRL_IDLE padding in upper positions
    //   for start blocks: data bytes after the implied start character


    // *: since this module is purely combinational, o_valid mirrors i_valid.


	logic [DATA_W/8-1:0] term_pos;

    	always_comb 
	begin
        	o_valid  = i_valid;
        	o_data   = '0; //no latches inferred
        	term_pos = i_keep + 8'd1;

        	// default: idle control block
        	o_data[65:64] = 2'b10;
        	o_data[7:0]   = BLOCK_TYPE_CTRL;
        	o_data[63:8]  = {8{CTRL_IDLE}};

	if (i_error) 
	begin
		// if known to be error, emit a don't care
        	o_data = 'x;
    	end
        else if (i_ctrl == 8'h00) 
	begin
        	// pure data block
        	o_data[65:64] = 2'b01;
        	o_data[63:0]  = i_data;
        end

        else if (i_idle) 
	begin
        	// all idle control block
        	o_data[65:64] = 2'b10;
         	o_data[7:0]   = BLOCK_TYPE_CTRL;
        	o_data[63:8]  = {8{CTRL_IDLE}};
        end

        else if (i_start) 
	begin
            	// start in lane 0: /S/ D1 D2 D3 D4 D5 D6 D7
            	o_data[65:64] = 2'b10;
            	o_data[7:0]   = BLOCK_TYPE_START_0;
            	o_data[63:8]  = i_data[63:8];
        end

        else if (i_terminate) 
	begin
        	o_data[65:64] = 2'b10;

        	unique case (term_pos)

                8'b0000_0001: 
		begin
                	// terminate in lane 0: /T/ C1 C2 C3 C4 C5 C6 C7
                	o_data[7:0]   = BLOCK_TYPE_TERM_0;	
                	o_data[63:15]  = {7{CTRL_IDLE}};
                end

                8'b0000_0010: 
		begin
                	// terminate in lane 1: D0 /T/ C2 C3 C4 C5 C6 C7
                	o_data[7:0]   = BLOCK_TYPE_TERM_1;
                	o_data[15:8]  = i_data[7:0];
                	o_data[63:22] = {6{CTRL_IDLE}};
                end

                8'b0000_0100: 
		begin
                	// terminate in lane 2: D0 D1 /T/ C3 C4 C5 C6 C7
                	o_data[7:0]   = BLOCK_TYPE_TERM_2;
                 	o_data[23:8]  = i_data[15:0];
                	o_data[63:29] = {5{CTRL_IDLE}};
                end

                8'b0000_1000: 
		begin
                	// terminate in lane 3: D0 D1 D2 /T/ C4 C5 C6 C7
                	o_data[7:0]   = BLOCK_TYPE_TERM_3;
                	o_data[31:8]  = i_data[23:0];
                	o_data[63:36] = {4{CTRL_IDLE}};
                end

                8'b0001_0000: 
		begin
                	// terminate in lane 4: D0 D1 D2 D3 /T/ C5 C6 C7
                	o_data[7:0]   = BLOCK_TYPE_TERM_4;
                 	o_data[39:8]  = i_data[31:0];
                	o_data[63:43] = {3{CTRL_IDLE}};
                end

                8'b0010_0000: 
		begin
                	// terminate in lane 5: D0 D1 D2 D3 D4 /T/ C6 C7
                   	o_data[7:0]   = BLOCK_TYPE_TERM_5;
                	o_data[47:8]  = i_data[39:0];
                	o_data[63:50] = {2{CTRL_IDLE}};
                end

                8'b0100_0000: 
		begin
                	// terminate in lane 6: D0 D1 D2 D3 D4 D5 /T/ C7
                	o_data[7:0]   = BLOCK_TYPE_TERM_6;
                	o_data[55:8]  = i_data[47:0];
                	o_data[63:57] = CTRL_IDLE;
                end

                8'b1000_0000: 
		begin
                	// terminate in lane 7: D0 D1 D2 D3 D4 D5 D6 /T/
                	o_data[7:0]   = BLOCK_TYPE_TERM_7;
                	o_data[63:8]  = i_data[55:0];
                end

                default: 
		begin
			// if not a vaild signal, emit a don't care
                	o_data = 'x;
                end

            endcase
        end
    end

endmodule