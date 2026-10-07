# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Design Compiler synthesis of X-HEEP (`make asic-dc TECH=<tech>`, fusesoc
# targets asic_dc_synthesis_<tech>), for every technology the flow of
# polheepo's TSMC65 DC script (compile_ultra -timing -gate_clock, hierarchy
# kept, the same checks and reports), aligned with the Yosys/OpenSTA flow so
# that the four tool/technology combinations compare:
#   - the same libraries and corner (scripts/asic/tech/<tech>.tcl,
#     $ASIC_CORNER) and constraints (scripts/synthesis/constraints.sdc);
#   - clock gating with the same integrated cell Yosys inserts (TECH_ICG_CELL,
#     min. 3 registers); no retiming (-retime), which Yosys cannot match;
#   - analysis as in OpenSTA: no wire-load model, primary-input activity
#     0.1 toggles/cycle (static probability 0.5) for the vectorless power.
#
# Sourced by the tcl project file of the edalize `design_compiler` backend,
# which defines SCRIPT_DIR (this directory), READ_SOURCES (the tcl that
# analyzes the RTL of the target) and REPORT_DIR. The pre_build hooks write,
# in the build directory (the current directory):
#   asic_tech.tcl              `set ASIC_TECH <tech>`
#   x_heep_system_dc_top.sv    the synthesis top (generate_dc_top.py)
#
# Outputs: netlist.v (top `x_heep_system`, see the end), netlist.sdc,
# constraints.sdc and the reports in $REPORT_DIR (copied by `make asic-dc`
# to implementation/synthesis/); precompiled.ddc and compiled.ddc in the
# build directory.
#
# Environment: ASIC_CLK_PERIOD (clk_i period [ns], default: the SDC's),
# ASIC_CORNER (worst, default, or typ), DC_CORES (default 16).

set dc_top x_heep_system_dc_top

if {[catch {
  source asic_tech.tcl
  source [file join $SCRIPT_DIR .. .. asic tech $ASIC_TECH.tcl]
  puts "\[x-heep] target technology: $ASIC_TECH, library corner: [asic_corner]"

  set cores [asic_env DC_CORES]
  if {$cores eq ""} { set cores 16 }
  set_host_options -max_cores $cores

  # Libraries
  remove_design -all
  set target_library [tech_dc_target_dbs]
  set link_library [concat "*" [tech_dc_link_dbs]]
  puts "------------------------------------------------------------------"
  puts "USED LIBRARIES"
  puts $link_library
  puts "------------------------------------------------------------------"

  # RTL: the edalize read-sources script one command at a time, stopping at
  # the first failed `analyze` (it would otherwise surface only later, as an
  # unresolved reference at link time)
  define_design_lib WORK -path ./work
  set fh [open ${READ_SOURCES}.tcl r]
  set read_cmds [split [read $fh] "\n"]
  close $fh
  foreach cmd $read_cmds {
    if {[string trim $cmd] eq "" || [string match "#*" [string trim $cmd]]} { continue }
    set res [uplevel #0 $cmd]
    if {[string match "analyze *" [string trim $cmd]] && !$res} {
      error "analyze failed (see the Error messages above): $cmd"
    }
  }
  if {![analyze -format sverilog $dc_top.sv]} { error "analyze of $dc_top.sv failed" }
  if {![elaborate $dc_top]} { error "elaboration of $dc_top failed" }
  current_design $dc_top
  if {![link]} { error "link of $dc_top failed (unresolved references)" }

  write -f ddc -hierarchy -output precompiled.ddc

  # Constraints (the same SDC as the Yosys flow)
  set sdc_file [file normalize [file join $SCRIPT_DIR .. constraints.sdc]]
  puts "\[x-heep] constraints: $sdc_file"
  source $sdc_file

  # As OpenSTA on the Yosys netlist (scripts/synthesis/opensta/sta_reports.tcl):
  # no wire-load model, primary inputs toggling 0.1 times per clock cycle
  # (the library's zero model, set explicitly: without a model DC falls back
  # on the library default, e.g. area-based selection on IHP, which picked 1k)
  set_app_var auto_wire_load_selection false
  set_wire_load_mode top
  set_wire_load_model -name $TECH_DC_ZERO_WIRE_LOAD
  set_app_var power_default_toggle_rate 0.1
  set_app_var power_default_static_probability 0.5
  file copy -force $sdc_file ${REPORT_DIR}/constraints.sdc

  report_clocks -attributes -skew > ${REPORT_DIR}/clocks.rpt

  set_clock_gating_style -minimum_bitwidth 3 -positive_edge_logic integrated:$TECH_ICG_CELL -control_point before

  check_design > ${REPORT_DIR}/check_design_elaborate.rpt
  check_timing > ${REPORT_DIR}/check_timing_elaborate.rpt

  # Needed by the gate-level simulation (not in polheepo's script): constant
  # outputs of hierarchical modules (e.g. the always-zero low bits of the CPU
  # fetch/data addresses) must stay driven, by tie cells, inside the module
  # that produces them. By default DC propagates such constants across
  # hierarchy boundaries even with -no_boundary_optimization, disconnects the
  # producer's pins and leaves the consumer's port bits with no driver at
  # all: Z in simulation, X on the bus after the first fetch.
  catch {set_app_var compile_enable_constant_propagation_with_no_boundary_opt false}
  uniquify
  foreach pattern {*/*tie* */*TIE*} {
    set ties [get_lib_cells -quiet $pattern]
    if {[sizeof_collection $ties] > 0} {
      # (set_dont_use cannot clear the attribute: remove it; not set -> ignored)
      catch {remove_attribute $ties dont_use}
      catch {remove_attribute $ties dont_touch}
    }
  }
  set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
  set_app_var verilogout_no_tri true

  compile_ultra -no_autoungroup -no_boundary_optimization -timing -gate_clock

  check_design > ${REPORT_DIR}/check_design_compile.rpt
  check_timing > ${REPORT_DIR}/check_timing_compile.rpt

  report_timing -loop -max_paths 10 > ${REPORT_DIR}/timing_loop.rpt

  write -f ddc -hierarchy -output compiled.ddc

  change_names -rules verilog -hier

  # Undriven nets simulate as Z (see above): surface them here rather than as
  # X in the gate-level simulation
  set fh [open ${REPORT_DIR}/check_design_compile.rpt r]
  set undriven [lsearch -all -inline [split [read $fh] "\n"] "*no driver*"]
  close $fh
  if {[llength $undriven] > 0} {
    puts "\[x-heep] WARNING: [llength $undriven] undriven net(s) after compile (see check_design_compile.rpt), e.g.:"
    foreach l [lrange $undriven 0 4] { puts "  $l" }
  }

  report_timing -nosplit > ${REPORT_DIR}/timing.rpt
  report_area -hier -nosplit > ${REPORT_DIR}/area.rpt
  report_resources -hierarchy > ${REPORT_DIR}/resources.rpt
  report_constraint > ${REPORT_DIR}/constraints.rpt
  report_clock_gating > ${REPORT_DIR}/clock_gating.rpt
  report_power > ${REPORT_DIR}/power.rpt
  # The nets with the highest switching power (to check the clock/pad groups)
  report_power -net -nworst 20 -nosplit > ${REPORT_DIR}/power_nets.rpt
  # To check that no wire-load model is in effect
  report_wire_load > ${REPORT_DIR}/wire_load.rpt
  report_qor > ${REPORT_DIR}/qor.rpt

  # Netlist: the wrapper becomes `x_heep_system` and the RTL top
  # `x_heep_system_core`, so that the netlist top has the name and the plain
  # port names/widths of the Yosys netlist (and of the testbench's instance)
  rename_design x_heep_system x_heep_system_core
  rename_design $dc_top x_heep_system
  current_design x_heep_system
  write -format verilog -hier -o ${REPORT_DIR}/netlist.v
  write_sdc -version 1.7 ${REPORT_DIR}/netlist.sdc
} err]} {
  puts "\[x-heep] ERROR: $err"
  exit 1
}

puts "\[x-heep] done: netlist and reports in ${REPORT_DIR}"
exit 0
