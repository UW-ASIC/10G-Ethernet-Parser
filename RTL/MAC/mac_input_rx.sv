`default_nettype none
// this module is purely combinational. clk/rst_n are included for optional output registering only.

module mac_input_rx #(
    parameter FIFO_W = 84,
    parameter DATA_W = 64
)(
    input  logic          clk,
    input  logic        rst_n,

    // Input
    input  logic                    tready,         // backpressure from the Ethernet parser
    input  logic [FIFO_W - 1 : 0]   PCS_out,        // 84 bit FIFO transport

    // Output
    output logic [DATA_W - 1 : 0]   tdata          // 64 bytes of data
);

logic [DATA_W - 1 : 0] tdata_buffer;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        tdata_buffer <= 64'b0;
    end else begin
        if (tready) begin
            tdata_buffer <= PCS_out[DATA_W - 1 : 0];
        end
    end
end

assign tdata = tdata_buffer;

endmodule
