# scrambler iso tb:

# from vivado tcl console run: 
# cd D:/10G-Ethernet-Parser-main (path to your local repo-)

# then: 
# source scripts/run_descrambler_tb.tcl

cd [file dirname [info script]]/..
 
puts [exec xvlog --sv RTL/PCS/descrambler.sv verification/RTL_tb/PCS/eth_frame_pkg.sv verification/RTL_tb/PCS/descrambler_iso_tb.sv]
puts [exec xelab descrambler_iso_tb -s descr_sim --timescale 1ns/1ps]
puts [exec xsim descr_sim -R]