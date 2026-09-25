# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Timing constraints of `x_heep_system_synth_top` for the Design Compiler
# flows (sourced by dc_script.tcl, after the technology description).
# Deliberately simple: they are meant to get a sensible, simulatable netlist,
# not a signed-off one (see polheepo's implementation/design_compiler for a
# complete, chip-level constraint set).

# System clock period [ns]: $ASIC_CLK_PERIOD, else the technology default.
set clk_period [asic_env ASIC_CLK_PERIOD]
if {$clk_period eq ""} { set clk_period $TECH_CLK_PERIOD }
# JTAG: at least 40 ns (25 MHz), asynchronous to the system clock.
set jtag_period [expr {max(40.0, 4.0 * $clk_period)}]
puts "\[x-heep] clocks: clk_i $clk_period ns, jtag_tck_i $jtag_period ns"

# The clock ports are pad-ring `inout`s: DC warns that defining a clock on an
# inout port is unusual (UID-376), which is fine here.
create_clock -name clk_sys  -period $clk_period  [get_ports clk_i]
create_clock -name clk_jtag -period $jtag_period [get_ports jtag_tck_i]
set_clock_groups -asynchronous -group clk_sys -group clk_jtag
set_clock_uncertainty [expr {0.05 * $clk_period}] [get_clocks clk_sys]

# Quasi-static or asynchronous inputs.
foreach p {rst_ni jtag_trst_ni boot_select_i execute_from_flash_i} {
  set port [get_ports -quiet $p]
  if {[sizeof_collection $port] > 0} { set_false_path -from $port }
}

# Budget 30% of the system clock cycle outside the chip for all other IOs.
set clk_ports [get_ports {clk_i jtag_tck_i}]
set_input_delay  [expr {0.3 * $clk_period}] -clock clk_sys [remove_from_collection [all_inputs] $clk_ports]
set_output_delay [expr {0.3 * $clk_period}] -clock clk_sys [all_outputs]
