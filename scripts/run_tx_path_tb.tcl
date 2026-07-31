# tx path tb: compile, elaborate, simulate
# from vivado tcl console: source scripts/run_tx_path_tb.tcl

cd [file dirname [info script]]/..

puts [exec xvlog --sv \
    RTL/PCS/encoder.sv \
    RTL/PCS/scrambler.sv \
    RTL/PCS/gearbox_tx.sv \
    verification/RTL_tb/PCS/eth_frame_pkg.sv \
    verification/RTL_tb/PCS/tx_path_tb.sv]
puts [exec xelab tx_path_tb -s tx_path_sim --timescale 1ns/1ps]
puts [exec xsim tx_path_sim -R]
