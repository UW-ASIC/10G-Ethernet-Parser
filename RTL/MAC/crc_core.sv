`default_nettype none

module CRC_core(
    input wire i_clk,
    input wire i_rstn,
    input wire [63:0] i_8xframe,
    input wire i_valid,
    input wire i_last, 
    input wire i_corrupt,
    output reg [31:0] o_crc
);

    localparam [31:0] init = 32'hFFFF_FFFF;
    localparam [31:0] poly_rev = 32'hEDB8_8320;

    function [31:0] crc_byte;
        input [31:0] c;
        input [7:0] b;
        integer i;
        begin 
            crc_byte = c^{24'h0, b};
            for (i=0; i<8; i=i+1)
                crc_byte = (crc_byte>>1)^(crc_byte[0] ? poly_rev : 32'h0);
        end
    endfunction 

    function [31:0] D;
        input [63:0] x;
        integer k;
        reg [31:0] c;
        begin
            c = 32'h0;
            for (k=0; k<8; k=k+1)
                c = crc_byte(c, x[8*k +: 8]);
                D = c;
        end
    endfunction

    function [31:0] A;
        input [31:0] s;
        integer k;
        reg [31:0] c;
        begin
            c = s;
            for (k=0; k<8; k=k+1)
                c = crc_byte(c, 8'h00);
            A = c;
        end
    endfunction

    reg [31:0] d_pipe;
    reg v_pipe, last_pipe;

    reg [31:0] state;
    reg corrupt_seen;
    wire [31:0] state_next = A(state)^d_pipe;

    always @(posedge i_clk) begin
        if (!i_rstn) begin
            d_pipe <= 32'h0;
            v_pipe <= 1'b0;
            last_pipe <= 1'b0;
            state <= init;
            corrupt_seen <= 1'b0;
            o_crc <= 32'h0;
        end else begin
            d_pipe <= D(i_8xframe);
            v_pipe <= i_valid;
            last_pipe <= i_valid & i_last;

            if (i_corrupt)
                corrupt_seen <= 1'b1;

            if (v_pipe) begin
                if (last_pipe) begin
                    o_crc <= ~state_next ^ (corrupt_seen ? 32'h0000_0001 : 32'h0);
                    state <= init;
                    corrupt_seen <= i_corrupt;
                end else begin
                    state <= state_next;
                end
            end
        end
    end

endmodule

`default_nettype wire