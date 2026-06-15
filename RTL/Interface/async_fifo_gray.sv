module async_fifo_gray #(

    parameter DATA_W = 32,
    parameter FIFO_DEPTH = 32
)(
    // Write side interface
    input  logic                wclk,       // write clock
    input  logic                wrst_n,     // active-low synchronous reset (write clock)
    input  logic [DATA_W-1:0]   wdata_in,   // write data
    input  logic                w_en,       // write enable
    output logic                wfull,      // fifo full

    // Read side interface
    input  logic                rclock,     // read clock
    input  logic                rrst_n,     // active_low synchronous reset (read clock)
    output logic [DATA_W-1:0]   rdata_out,  // read data
    input  logic                r_en,       // read enable
    output logic                rempty      // fifo empty
);



endmodule