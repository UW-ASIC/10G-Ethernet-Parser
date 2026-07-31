# scrambler iso tb:

# from vivado tcl console run: 
# cd D:/10G-Ethernet-Parser-main (path to your local repo-)

# then: 
# source scripts/run_gearbox_tx_tb.tcl

cd [file dirname [info script]]/..
 
puts [exec xvlog --sv RTL/PCS/gearbox_tx.sv verification/RTL_tb/PCS/eth_frame_pkg.sv verification/RTL_tb/PCS/gearbox_tx_iso_tb.sv]
puts [exec xelab gearbox_tx_iso_tb -s gearbox_sim --timescale 1ns/1ps]
puts [exec xsim gearbox_sim -R]