`default_nettype none
`timescale 1ns / 1ps

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a VCD file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rstn;
  reg [63:0] i_8xframe;
  reg i_valid;
  reg i_last;
  reg i_corrupt;
  wire [31:0] o_crc;

  // Instantiate control_MAC_learning:
  CRC_core dut (
      .i_clk    (clk),       
      .i_rstn   (rstn),      
      .i_8xframe  (i_8xframe),     
      .i_valid (i_valid),     
      .i_last    (i_last),  
      .i_corrupt (i_corrupt),      
      .o_crc(o_crc)  
  );

endmodule
