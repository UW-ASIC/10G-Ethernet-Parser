# build_pcs_tmp_wrapper.tcl
# Fetches the PCS from GitHub and creates a Vivado project
# No local clone needed.

# from vivado tcl console:
# source {path}/build_pcs_tmp_wrapper.tcl

set repo_url  "https://github.com/UW-ASIC/10G-Ethernet-Parser.git"
set branch    "PCS"
set proj_name "pcs_synth_check"
set proj_dir  [file normalize [file join [pwd] ${proj_name}]]
set part      "xczu7ev-ffvc1156-2-e"
set clone_dir "${proj_dir}/_repo"

# clean previous run
if {[file exists ${proj_dir}]} {
    puts "Removing existing project..."
    file delete -force ${proj_dir}
}

# fetch from github
puts "Cloning ${repo_url} (branch: ${branch})..."
file mkdir ${proj_dir}
file delete -force ${clone_dir}
exec git clone --depth 1 --branch ${branch} ${repo_url} ${clone_dir} 2>@1

# create project
create_project ${proj_name} ${proj_dir} -part ${part}
set_property target_language Verilog [current_project]

# design sources: RTL/PCS/*.sv
add_files -norecurse [glob ${clone_dir}/RTL/PCS/*.sv]

# wrapper: FPGA/tmp_files/pcs_wrapper.sv
add_files -norecurse ${clone_dir}/FPGA/tmp_files/pcs_wrapper.sv

# set all to SystemVerilog
set_property file_type SystemVerilog [get_files *.sv]

# set top
set_property top PCS_top_wrapper [current_fileset]
update_compile_order -fileset sources_1

# sim sources: verification/RTL_tb/PCS/*.sv
set sim_files [glob ${clone_dir}/verification/RTL_tb/PCS/*.sv]
add_files -fileset sim_1 -norecurse ${sim_files}
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
update_compile_order -fileset sim_1

# constraints: hardware/consts.xdc
add_files -fileset constrs_1 -norecurse ${clone_dir}/hardware/consts.xdc

puts ""
puts "--------------------------------------------------"
puts "  Project:     ${proj_dir}"
puts "  Part:        ${part} (ZCU106)"
puts "  Top:         pcs_wrapper"
puts "  Clock:       156.25 MHz (6.4ns)"
puts "  RTL:         RTL/PCS/*.sv"
puts "  Sim:         verification/RTL_tb/PCS/*.sv"
puts "  Constraints: hardware/consts.xdc"
puts ""
puts "  launch_runs synth_1 -jobs 4"
puts "  launch_runs impl_1 -jobs 4"
puts "  report_timing_summary"
puts "--------------------------------------------------"

start_gui