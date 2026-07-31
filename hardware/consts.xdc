create_clock -period 6.400 -name clk [get_ports clk]
set_false_path -from [get_ports {serdes_rx_* mac_tx_* rst_n}]
set_false_path -to   [get_ports {serdes_tx_* mac_rx_* mac_tx_accept block_lock}]