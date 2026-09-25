# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Design Compiler synthesis of X-HEEP for the ASIC flows `asic_dc_<tech>`
# (tech: ihp130 = IHP-SG13G2, tsmc65 = TSMC 65nm LP; see `make dc-<tech>`).
#
# Sourced by the tcl project file of the edalize `design_compiler` backend,
# which defines SCRIPT_DIR (this directory), READ_SOURCES (the tcl that
# analyzes the RTL of the fusesoc target) and REPORT_DIR. The pre_build hooks
# of the target write, in the build directory (the current directory):
#   asic_tech.tcl                `set ASIC_TECH <tech>`
#   x_heep_system_synth_top.sv   the synthesis top (generate_xif_tieoff_wrapper.py
#                                --plain-ports: x_heep_system minus the xif
#                                interface ports, struct ports as plain vectors)
#
# Outputs, in the build directory:
#   x_heep_system_netlist.v      gate-level netlist (top: x_heep_system_synth_top),
#                                staged for simulation by `make dc-<tech>-stage-netlist`
#   x_heep_system_netlist.{sdc,sdf,ddc}
#   $REPORT_DIR/*.rpt
#
# Hierarchy is kept (-no_autoungroup -no_boundary_optimization), as in the
# yosys flows and in polheepo, so the RTL instance paths survive synthesis.
#
# Environment: ASIC_CLK_PERIOD (ns, default: TECH_CLK_PERIOD of the
# technology), DC_CORES (default 8).

set synth_top x_heep_system_synth_top

if {[catch {
  source asic_tech.tcl
  source [file join $SCRIPT_DIR .. .. asic tech $ASIC_TECH.tcl]
  puts "\[x-heep] target technology: $ASIC_TECH"

  set cores [asic_env DC_CORES]
  if {$cores eq ""} { set cores 8 }
  set_host_options -max_cores $cores

  # Libraries
  set target_library [tech_dc_target_dbs]
  set link_library [concat "*" [tech_dc_link_dbs]]
  puts "\[x-heep] target_library: $target_library"
  puts "\[x-heep] link_library:   $link_library"

  # RTL
  remove_design -all
  define_design_lib WORK -path ./work
  # Run the edalize read-sources script one command at a time, stopping at the
  # first failed `analyze` (which would otherwise only surface later as an
  # unresolved reference at link time).
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
  if {![analyze -format sverilog $synth_top.sv]} { error "analyze of $synth_top.sv failed" }
  if {![elaborate $synth_top]} { error "elaboration of $synth_top failed" }
  current_design $synth_top
  if {![link]} { error "link of $synth_top failed (unresolved references)" }
  check_design > ${REPORT_DIR}/check_design_elab.rpt
  write -format ddc -hierarchy -output ${REPORT_DIR}/elaborated.ddc

  # Constraints
  source [file join $SCRIPT_DIR constraints.tcl]
  report_clocks > ${REPORT_DIR}/clocks.rpt
  check_timing > ${REPORT_DIR}/check_timing.rpt

  # Drive constant and feedthrough port nets of every module with real cells
  # (tie cells / buffers). Otherwise constant output bits of a hierarchical
  # module (e.g. the always-zero low bits of the CPU fetch address) can be
  # written to the netlist with no driver at all: they simulate as Z, and the
  # bus logic they feed turns X (seen on dc-ihp130). Also needed for PnR.
  # The tie cells must be usable for that.
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

  # Compile
  if {$TECH_DC_GATE_CLOCK} {
    set_clock_gating_style -minimum_bitwidth 3 -positive_edge_logic integrated -control_point before
    compile_ultra -no_autoungroup -no_boundary_optimization -gate_clock
  } else {
    compile_ultra -no_autoungroup -no_boundary_optimization
  }
  check_design > ${REPORT_DIR}/check_design_compile.rpt

  # Outputs
  change_names -rules verilog -hierarchy
  write -format ddc -hierarchy -output x_heep_system_netlist.ddc
  write -format verilog -hierarchy -output x_heep_system_netlist.v
  write_sdc x_heep_system_netlist.sdc
  write_sdf x_heep_system_netlist.sdf

  # Reports
  report_qor > ${REPORT_DIR}/qor.rpt
  report_timing -nosplit -max_paths 20 > ${REPORT_DIR}/timing.rpt
  report_constraint -all_violators -nosplit > ${REPORT_DIR}/constraints.rpt
  report_area -hierarchy -nosplit > ${REPORT_DIR}/area.rpt
  report_power -nosplit > ${REPORT_DIR}/power.rpt
  report_reference -hierarchy -nosplit > ${REPORT_DIR}/references.rpt
  if {$TECH_DC_GATE_CLOCK} { report_clock_gating -nosplit > ${REPORT_DIR}/clock_gating.rpt }
} err]} {
  puts "\[x-heep] ERROR: $err"
  exit 1
}

puts "\[x-heep] done: x_heep_system_netlist.v (reports in ${REPORT_DIR})"
exit 0
