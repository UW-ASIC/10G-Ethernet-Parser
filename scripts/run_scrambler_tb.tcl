# scrambler iso tb:

# from vivado tcl console run: 
# cd D:/10G-Ethernet-Parser-main (path to your local repo-)

# then: 
# source scripts/run_scrambler_tb.tcl

cd [file dirname [info script]]/..
 
puts [exec xvlog --sv RTL/PCS/scrambler.sv verification/RTL_tb/PCS/eth_frame_pkg.sv verification/RTL_tb/PCS/scrambler_iso_tb.sv]
puts [exec xelab scrambler_iso_tb -s scr_sim --timescale 1ns/1ps]
puts [exec xsim scr_sim -R]