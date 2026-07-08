`default_nettype none
// this module is purely combinational. clk/rst_n are included for optional output registering only.

`include "mac_rx_interface.sv"
`include "mac_tx_interface.sv"

module mac_interface #(
    parameter FIFO_W = 84,
    parameter DATA_W = 64
)(
    input  logic          clk,
    input  logic        rst_n,

    // Rx
    // input from async FIFO from 10G-Base-R PCS
    input  logic                    rx_tready,      // backpressure from the Ethernet parser, if low, hold its output stable until the parser is ready
    input  logic [FIFO_W - 1 : 0]   rx_PCS_out,     // 84 bit FIFO transport

    // output to AXL_S to Frame Parser
    output logic                    rx_tvalid,      // MAC module complete
    output logic                    rx_tlast,       // High on the final beat of the frame
    output logic [DATA_W - 1 : 0]   rx_tdata,       // 64 bytes of data
    output logic [7 : 0]            rx_tkeep,       // Data indicator, `0xFF` on every beat except the last
    output logic                    rx_tuser,        // Error flag: high, CRC-32 check failed and downstream should discard the entire frame

    // Tx
    // input from AXL_S from Frame Parser
    input logic                    tx_tvalid,       // MAC module complete
    input logic                    tx_tlast,        // High on the final beat of the frame
    input logic [DATA_W - 1 : 0]   tx_tdata,        // 64 bytes of data
    input logic [7 : 0]            tx_tkeep,        // Data indicator, `0xFF` on every beat except the last
    input logic                    tx_tuser,        // Error flag: high, CRC-32 check failed and downstream should discard the entire frame

    // output to async FIFO to 10G-Base-R PCS
    output  logic                    tx_tready,     // backpressure from the Ethernet parser, if low, hold its output stable until the parser is ready
    output  logic [FIFO_W - 1 : 0]   tx_PCS_out     // 84 bit FIFO transport

);

    // MAC Interface
    mac_rx_interface mac_rx_interface_inst (
        .clk(clk), .rst_n(rst_n),

        .tready(rx_tready), .PCS_out(rx_PCS_out),
        .tvalid(rx_tvalid), .tlast(rx_tlast), .tdata(rx_tdata),

        .tkeep(rx_tkeep), .tuser(rx_tuser)
    );

    mac_tx_interface mac_tx_interface_inst (
        .clk(clk), .rst_n(rst_n),

        .tvalid(tx_tvalid), .tlast(tx_tlast), .tdata(tx_tdata),
        .tkeep(tx_tkeep), .tuser(tx_tuser),

        .tready(tx_tready), .PCS_out(tx_PCS_out)
    );

   
endmodule
