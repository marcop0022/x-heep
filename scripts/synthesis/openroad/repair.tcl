# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Electrical repair of a Yosys netlist with OpenROAD (`make asic-yosys-repair`,
# run by run_repair.sh):
#
#   XHEEP_SYNTH_OUT=<Yosys output> XHEEP_REPAIR_OUT=<new output folder> \
#     [XHEEP_REPAIR_NETLIST=<netlist of prep.tcl>] \
#     openroad -no_init -no_splash -exit scripts/synthesis/openroad/repair.tcl
#
# The netlist is XHEEP_REPAIR_NETLIST (default: the Yosys netlist.v), the
# technology, corner, clock period and constraints those of XHEEP_SYNTH_OUT.
#
# Design Compiler buffers high-fanout nets and optimizes the timing inside
# compile_ultra; the open-source flow leaves this to physical design. This
# step does it on the Yosys netlist before placement, with the libraries,
# corner and constraints of the synthesis:
#   insert_tiecells tie cells (TECH_TIE_LO/HI) for any constant left: OpenROAD
#                   writes constants as undriven zero_/one_ nets (prep.tcl
#                   already drives them with tie cells, as Design Compiler);
#   repair_design   buffering/resizing for the library's max fanout,
#                   transition and capacitance;
#   repair_timing   setup-driven resizing, buffering, cloning
#                   (skipped with XHEEP_REPAIR_TIMING=0).
# As in the other flows there is no wire load: the library's zero model
# (TECH_DC_ZERO_WIRE_LOAD), since OpenROAD would otherwise fall back on the
# library's default wire-load models before placement.
# Writes netlist.v (flat) and repair.rpt (cells, buffers, runtime) into
# XHEEP_REPAIR_OUT. The timing, power, ... reports are those of OpenSTA
# (sta_reports.tcl), as for every netlist.

# Repository root: $XHEEP_ROOT (set by run_repair.sh), since OpenROAD does not
# give the script its own path (info script)
if {[info exists ::env(XHEEP_ROOT)] && $::env(XHEEP_ROOT) ne ""} {
  set root [file normalize $::env(XHEEP_ROOT)]
} else {
  set root [file normalize [file join [file dirname [info script]] .. .. ..]]
}
if {![file exists $root/scripts/asic/tech/common.tcl]} {
  error "\[x-heep] repository root not found ($root): set \$XHEEP_ROOT"
}
foreach v {XHEEP_SYNTH_OUT XHEEP_REPAIR_OUT} {
  if {![info exists ::env($v)]} { error "\[x-heep] \$$v is not set" }
}
set in [file normalize $::env(XHEEP_SYNTH_OUT)]
set out [file normalize $::env(XHEEP_REPAIR_OUT)]
set netlist $in/netlist.v
if {[info exists ::env(XHEEP_REPAIR_NETLIST)] && $::env(XHEEP_REPAIR_NETLIST) ne ""} {
  set netlist [file normalize $::env(XHEEP_REPAIR_NETLIST)]
}
set do_timing [expr {![info exists ::env(XHEEP_REPAIR_TIMING)] || $::env(XHEEP_REPAIR_TIMING) ne "0"}]

proc xh_read {path} {
  set f [open $path]
  set s [string trim [read $f]]
  close $f
  return $s
}

# Technology, corner and clock period of the synthesis
set tech [xh_read $in/asic_tech]
if {[file exists $in/asic_corner]} { set ::env(ASIC_CORNER) [xh_read $in/asic_corner] }
if {[file exists $in/asic_clk_period] && [xh_read $in/asic_clk_period] ne ""} {
  set ::env(ASIC_CLK_PERIOD) [xh_read $in/asic_clk_period]
}
# (from its own folder: the tech file sources common.tcl next to it through
# info script, which is empty in OpenROAD)
set here [pwd]
cd $root/scripts/asic/tech
source $tech.tcl
cd $here
puts "\[x-heep] OpenROAD repair of $in ($tech, corner [asic_corner])"

foreach lef [tech_lef_files] { read_lef $lef }
read_liberty [lindex [tech_stdcell_libs] 0]
foreach lib [tech_yosys_macro_libs] { read_liberty $lib }
read_verilog $netlist
link_design x_heep_system
read_sdc $in/constraints.sdc
# (the std-cell library's model: the IO Liberty may define one with the same name)
set std_lib [file rootname [file tail [lindex [tech_stdcell_libs] 0]]]
if {[catch {set_wire_load_model -name $TECH_DC_ZERO_WIRE_LOAD -library $std_lib} err]} {
  puts "\[x-heep] set_wire_load_model -library $std_lib: $err; retrying without -library"
  set_wire_load_model -name $TECH_DC_ZERO_WIRE_LOAD
}

set rpt [list "OpenROAD electrical repair of [file tail $in] ($tech, corner [asic_corner])"]
proc step {name} {
  global rpt t0
  set n [llength [get_cells -hierarchical *]]
  set line [format "%-22s %8d instances  %6d s" $name $n [expr {[clock seconds] - $t0}]]
  puts "\[x-heep] $line"
  lappend rpt $line
}
set t0 [clock seconds]
step "netlist (Yosys)"
insert_tiecells $TECH_TIE_LO -prefix TIE_ZERO_
insert_tiecells $TECH_TIE_HI -prefix TIE_ONE_
step "insert_tiecells"
repair_design
step "repair_design"
if {$do_timing} {
  repair_timing -setup
  step "repair_timing -setup"
}

write_verilog $out/netlist.v
lappend rpt "Leaf cells: [llength [get_cells -hierarchical *]]"
lappend rpt "Runtime: [expr {[clock seconds] - $t0}] s"
set f [open $out/repair.rpt w]
puts $f [join $rpt "\n"]
close $f
puts "\[x-heep] OpenROAD repair done: $out/netlist.v"
