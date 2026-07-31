# gearbox_tx full flow: project -> synth -> impl -> post-impl functional sim
# run: vivado -mode batch -source run_gearbox_tx.tcl
# or from an open vivado tcl console: source run_gearbox_tx.tcl

set PROJ_NAME  gearbox_tx_flow
set PROJ_DIR   ./vivado_out/$PROJ_NAME
set PART       xcvu9p-flga2104-2L-e

set RTL_FILES {
    ../RTL/PCS/gearbox_tx.sv
}

set SIM_FILES {
    ./eth_frame_pkg.sv
    ./gearbox_tx_demo_tb.sv
}

set TB_TOP  gearbox_tx_demo_tb
set RTL_TOP gearbox_tx

# ----------------------------------------------------------------------------
file mkdir $PROJ_DIR
create_project $PROJ_NAME $PROJ_DIR -part $PART -force

add_files -norecurse $RTL_FILES
set_property top $RTL_TOP [current_fileset]

add_files -fileset sim_1 -norecurse $SIM_FILES
set_property top $TB_TOP [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

# synth
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    error "synthesis failed"
}

# impl
launch_runs impl_1 -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    error "implementation failed"
}

# reports worth glancing at before trusting the sim
open_run impl_1
report_utilization -file $PROJ_DIR/util.rpt
report_timing_summary -file $PROJ_DIR/timing.rpt
close_design

# post-impl functional sim
launch_simulation -mode post-implementation -type functional
run all