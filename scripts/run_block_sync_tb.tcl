# decoder iso tb:

# from vivado tcl console run: 
# cd D:/10G-Ethernet-Parser-main (path to your local repo-)

# then: 
# source scripts/run_block_sync_tb.tcl

cd [file dirname [info script]]/..
 
puts [exec xvlog --sv RTL/PCS/block_sync.sv verification/RTL_tb/PCS/eth_frame_pkg.sv verification/RTL_tb/PCS/block_sync_iso_tb.sv]
puts [exec xelab block_sync_iso_tb -s dec_sim --timescale 1ns/1ps]
puts [exec xsim dec_sim -R]