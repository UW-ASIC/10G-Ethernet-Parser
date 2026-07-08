`default_nettype none
// this module is purely combinational. clk/rst_n are included for optional output registering only.

`include "mac_input_tx.sv"

module mac_tx_interface #(
    parameter FIFO_W = 84,
    parameter DATA_W = 64
)(
    input  logic          clk,
    input  logic        rst_n,

    // input from AXL_S from Frame Parser
    input logic                    tvalid,         // MAC module complete
    input logic                    tlast,          // High on the final beat of the frame
    input logic [DATA_W - 1 : 0]   tdata,          // 64 bytes of data
    input logic [7 : 0]            tkeep,          // Data indicator, `0xFF` on every beat except the last
    input logic                    tuser,          // Error flag: high, CRC-32 check failed and downstream should discard the entire frame

    // output to async FIFO to 10G-Base-R PCS
    output  logic                    tready,         // backpressure from the Ethernet parser, if low, hold its output stable until the parser is ready
    output  logic [FIFO_W - 1 : 0]   PCS_out         // 84 bit FIFO transport

);


endmodule
