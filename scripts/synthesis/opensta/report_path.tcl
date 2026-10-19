# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Detailed OpenSTA analysis of the worst paths to (and optionally from) some
# cells of a synthesis netlist, loaded exactly as by sta_reports.tcl (same
# libraries, corner, clock period and constraints). For debugging a path:
#
#   XHEEP_SYNTH_OUT=<synthesis output folder> XHEEP_PATH_TO=<glob> [XHEEP_PATH_FROM=<glob>] \
#     sta -no_init -no_splash -exit scripts/synthesis/opensta/report_path.tcl | tee path.log
#
# The globs match full instance names (e.g. "*gen_gpios*19*i_sync_gpio_input*",
# the default of XHEEP_PATH_TO: the input synchronizer of GPIO 19);
# XHEEP_PATH_TO=all analyses the worst paths of the whole design. Printed:
#   1. the worst paths to those cells, with all the pins (hierarchical too);
#   2. the worst path point by point: delay of each step, cell, and the
#      top-level ports it goes through (i.e. through an IO pad);
#   3. the connections of the net where the path has its largest step.

set root [file normalize [file join [file dirname [info script]] .. .. ..]]
if {![info exists ::env(XHEEP_SYNTH_OUT)]} {
  error "\[x-heep] \$XHEEP_SYNTH_OUT is not set: the synthesis output folder to analyse"
}
set out [file normalize $::env(XHEEP_SYNTH_OUT)]
set to_glob "*gen_gpios*19*i_sync_gpio_input*"
if {[info exists ::env(XHEEP_PATH_TO)] && $::env(XHEEP_PATH_TO) ne ""} { set to_glob $::env(XHEEP_PATH_TO) }
set from_glob ""
if {[info exists ::env(XHEEP_PATH_FROM)]} { set from_glob $::env(XHEEP_PATH_FROM) }

proc xh_read {path} {
  set f [open $path]
  set s [string trim [read $f]]
  close $f
  return $s
}

# ---- Design, as in sta_reports.tcl ----
set tech [xh_read $out/asic_tech]
source $root/scripts/asic/tech/$tech.tcl
if {[file exists $out/asic_clk_period]} {
  set clk_period [xh_read $out/asic_clk_period]
  if {$clk_period ne ""} { set ::env(ASIC_CLK_PERIOD) $clk_period } else { unset -nocomplain ::env(ASIC_CLK_PERIOD) }
}
if {[file exists $out/asic_corner]} { set ::env(ASIC_CORNER) [xh_read $out/asic_corner] }
puts "\[x-heep] $out: $tech, corner [asic_corner], synthesis tool [xh_read $out/synth_tool]"
read_liberty [lindex [tech_stdcell_libs] 0]
foreach lib [tech_yosys_macro_libs] { read_liberty $lib }
read_verilog $out/netlist.v
link_design x_heep_system
read_sdc $out/constraints.sdc

# ---- The leaf cells (library cells) matching a glob on their full name ----
proc xh_cells {glob} {
  set cells {}
  foreach c [get_cells -hierarchical *] {
    if {![string match $glob [get_full_name $c]]} { continue }
    if {[catch {get_property $c liberty_cell} lib] || $lib eq ""} { continue }
    lappend cells $c
  }
  return $cells
}

# XHEEP_PATH_TO=all: the worst paths of the whole design (as timing.rpt)
set path_args {}
if {$to_glob eq "all"} {
  puts "\[x-heep] XHEEP_PATH_TO=all: the worst path of each path group"
} else {
  set to_cells [xh_cells $to_glob]
  puts "\[x-heep] XHEEP_PATH_TO=$to_glob: [llength $to_cells] cell(s)"
  foreach c $to_cells { puts "  [get_full_name $c] ([get_property $c ref_name])" }
  if {[llength $to_cells] == 0} { error "\[x-heep] no cell matches $to_glob" }
  lappend path_args -to $to_cells
}
if {$from_glob ne ""} {
  set from_cells [xh_cells $from_glob]
  puts "\[x-heep] XHEEP_PATH_FROM=$from_glob: [llength $from_cells] cell(s)"
  if {[llength $from_cells] == 0} { error "\[x-heep] no cell matches $from_glob" }
  lappend path_args -from $from_cells
}

# ---- 1. Worst paths, all the pins ----
set fields {input_pins hierarchical_pins capacitance slew fanout}
if {$to_glob eq "all"} {
  puts "\n==== 1. Worst setup path of each path group ===="
  report_checks -path_delay max -format full_clock_expanded -fields $fields -digits 3
} else {
  puts "\n==== 1. Worst setup paths (3 per endpoint) ===="
  if {[catch {report_checks {*}$path_args -path_delay max -format full_clock_expanded \
                -fields $fields -digits 3 -endpoint_path_count 3 -unique_paths_to_endpoint}]} {
    report_checks {*}$path_args -path_delay max -format full_clock_expanded \
      -fields $fields -digits 3 -endpoint_count 3 -unique_paths_to_endpoint
  }
}

# ---- 2. Worst path, point by point ----
puts "\n==== 2. Worst path, point by point ===="
set big_pin ""
if {[catch {
  # The path ends come grouped by path group (asynchronous first): take the
  # one with the worst slack
  set path_end ""
  foreach pe [find_timing_paths {*}$path_args -path_delay max] {
    if {$path_end eq "" || [get_property $pe slack] < [get_property $path_end slack]} { set path_end $pe }
  }
  if {$path_end eq ""} { error "no path found" }
  puts "Slack [format %.3f [get_property $path_end slack]] ns, endpoint [get_full_name [get_property $path_end endpoint]]"
  set prev ""
  set big 0.0
  set ports {}
  puts [format "%10s %10s  %-14s %s" "arrival" "step" "cell" "pin"]
  foreach pt [get_property $path_end points] {
    set pin [get_property $pt pin]
    set arr [get_property $pt arrival]
    set step [expr {$prev eq "" ? 0.0 : $arr - $prev}]
    set prev $arr
    set name [get_full_name $pin]
    if {![catch {get_property $pin is_port} is_port] && $is_port} {
      set ref "(top port)"
      lappend ports $name
    } elseif {[catch {get_property [get_cells -of_objects $pin] ref_name} ref]} {
      set ref "?"
    }
    puts [format "%10.3f %10.3f  %-14s %s" $arr $step $ref $name]
    if {$step > $big} { set big $step; set big_pin $pin }
  }
  puts "\nLargest step: [format %.3f $big] ns, ending at [get_full_name $big_pin]"
  if {[llength $ports] > 0} {
    puts "Top-level ports on the path (IO pads): [join $ports {, }]"
  } else {
    puts "Top-level ports on the path: none"
  }
} err]} {
  puts "\[x-heep] point-by-point listing not available in this OpenSTA version: $err"
}

# ---- 3. The net of the largest step ----
if {$big_pin ne ""} {
  puts "\n==== 3. Net driving [get_full_name $big_pin] ===="
  if {[catch {
    foreach net [get_nets -of_objects $big_pin] { report_net -digits 3 $net }
  } err]} {
    puts "\[x-heep] report_net failed: $err"
  }
}

puts "\n\[x-heep] report_path done"
