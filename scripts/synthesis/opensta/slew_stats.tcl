# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Electrical quality of a synthesis netlist (OpenSTA): how slow its signals
# switch and how many electrical limits of the library it violates, to compare
# netlists with and without electrical repair (e.g. Yosys with ASIC_ABC_SIZING=1
# against the same flow without it, and against Design Compiler). Printed:
#   - number of max transition, max capacitance and max fanout violations;
#   - the distribution of the transition times at the output pins of the cells;
#   - the slowest output pins, with their cell.
#
# Usage: XHEEP_SYNTH_OUT=<synthesis output folder> sta -no_init -no_splash -exit slew_stats.tcl
# (libraries, netlist and constraints as in sta_reports.tcl)

set root [file normalize [file join [file dirname [info script]] .. .. ..]]
if {![info exists ::env(XHEEP_SYNTH_OUT)]} {
  error "\[x-heep] \$XHEEP_SYNTH_OUT is not set: the synthesis output folder to analyse"
}
set out [file normalize $::env(XHEEP_SYNTH_OUT)]

proc xh_read {path} {
  set f [open $path]
  set s [string trim [read $f]]
  close $f
  return $s
}

set tech [xh_read $out/asic_tech]
source $root/scripts/asic/tech/$tech.tcl
if {[file exists $out/asic_clk_period]} {
  set clk_period [xh_read $out/asic_clk_period]
  if {$clk_period ne ""} { set ::env(ASIC_CLK_PERIOD) $clk_period } else { unset -nocomplain ::env(ASIC_CLK_PERIOD) }
}
if {[file exists $out/asic_corner]} { set ::env(ASIC_CORNER) [xh_read $out/asic_corner] }
read_liberty [lindex [tech_stdcell_libs] 0]
foreach lib [tech_yosys_macro_libs] { read_liberty $lib }
read_verilog $out/netlist.v
link_design x_heep_system
read_sdc $out/constraints.sdc

set sizing ""
if {[file exists $out/asic_abc_sizing]} { set sizing ", ABC sizing [xh_read $out/asic_abc_sizing]" }
puts "\[x-heep] slew-stats [file tail $out] ([xh_read $out/synth_tool], $tech$sizing)"

# Timing first, as in sta_reports.tcl (the slack of each path group is in the
# timing.rpt of the synthesis output, and in the metrics CSV)
sta::redirect_string_begin
report_checks -path_delay max -digits 3
sta::redirect_string_end

# Violations of the electrical limits of the library
foreach check {max_slew max_capacitance max_fanout} {
  sta::redirect_string_begin
  catch {report_check_types -$check -violators -digits 3}
  set text [sta::redirect_string_end]
  puts "\[x-heep] $check violations: [regexp -all {\(VIOLATED\)} $text]"
}

# Transition times at the output pins of the cells
set bins {0.1 0.25 0.5 1.0 2.5 10.0 50.0}
set counts [lrepeat [expr {[llength $bins] + 1}] 0]
set slow {}
set n 0
set prop ok
foreach cell [get_cells -hierarchical *] {
  if {[catch {get_property $cell liberty_cell} lc] || $lc eq ""} { continue }
  foreach pin [get_pins -of_objects $cell] {
    if {[catch {get_property $pin direction} d] || $d ne "output"} { continue }
    if {[catch {get_property $pin slew_max} s] || ![string is double -strict $s]} {
      set prop "slew_max: $s"
      break
    }
    incr n
    set i 0
    while {$i < [llength $bins] && $s >= [lindex $bins $i]} { incr i }
    lset counts $i [expr {[lindex $counts $i] + 1}]
    lappend slow [list $s [get_full_name $pin] [get_property $cell ref_name]]
  }
  if {$prop ne "ok"} { break }
}
if {$prop ne "ok"} {
  puts "\[x-heep] ERROR: cannot read the pin transitions ($prop)"
} else {
  puts "\[x-heep] transition at the $n output pins (ns):"
  set lo 0
  for {set i 0} {$i <= [llength $bins]} {incr i} {
    set hi [expr {$i < [llength $bins] ? [lindex $bins $i] : "inf"}]
    puts [format "\[x-heep]   %6s - %-6s %8d  (%5.2f%%)" $lo $hi [lindex $counts $i] [expr {100.0 * [lindex $counts $i] / $n}]]
    set lo $hi
  }
  puts "\[x-heep] slowest output pins:"
  foreach e [lrange [lsort -real -decreasing -index 0 $slow] 0 9] {
    lassign $e s p r
    puts [format "\[x-heep]   %9.3f ns  %-22s %s" $s $r $p]
  }
}
puts "\[x-heep] slew-stats done"
