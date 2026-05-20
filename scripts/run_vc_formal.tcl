# =============================================================================
# Project: GPU Tensor Core MAC Unit Verifier
# Script: run_vc_formal.tcl
# Description: Synopsys VC Formal execution script. Elaborates and runs proof.
# =============================================================================

# Set formal home and setup environments
set formal_run_mode "batch"

# Read design and assertion files
read_file -format verilog -sverilog {
    ../rtl/mac_unit.sv
    ../tb/mac_sva.sv
    ../tb/mac_bind.sv
}

# Elaborate top level design with default parameters
elaborate -top mac_unit -parameters {INPUT_WIDTH=16 ACCUM_WIDTH=32}

# Define clocking and reset parameters
create_clock clk -period 10
create_reset rst_n -sense active_low

# Enable SVA assertion checking
check_fv -init

# Run proof engines for bounded and unbounded verification
prove -bg -engine {seq bmc ind} -timeout 1800

# Generate summary report files
report_fv -summary -file formal_results.rpt
report_fv -assertions -file detailed_assertions.rpt

# Exit VC Formal
exit
