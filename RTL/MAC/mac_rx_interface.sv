`default_nettype none
// this module is purely combinational. clk/rst_n are included for optional output registering only.

`include "mac_input_rx.sv"

module mac_rx_interface #(
    parameter FIFO_W = 84,
    parameter DATA_W = 64
)(
    input  logic          clk,
    input  logic        rst_n,

    // input from async FIFO from 10G-Base-R PCS
    input  logic                    tready,         // backpressure from the Ethernet parser, if low, hold its output stable until the parser is ready
    input  logic [FIFO_W - 1 : 0]   PCS_out,        // 84 bit FIFO transport

    // output to AXL_S to Frame Parser
    output logic                    tvalid,         // MAC module complete
    output logic                    tlast,          // High on the final beat of the frame
    output logic [DATA_W - 1 : 0]   tdata,          // 64 bytes of data
    output logic [7 : 0]            tkeep,          // Data indicator, `0xFF` on every beat except the last
    output logic                    tuser           // Error flag: high, CRC-32 check failed and downstream should discard the entire frame
);

    mac_input_rx mac_input_rx_inst (
        .clk(clk), .rst_n(rst_n),

        .tready(tready), .PCS_out(PCS_out),

        .tdata(tdata)
    );


endmodule
