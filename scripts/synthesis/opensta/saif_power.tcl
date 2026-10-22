# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# OpenSTA power of a synthesis netlist with the switching activity of a
# gate-level simulation (`make thesis-power`, scripts/synthesis/thesis_power.sh).
#
# The SAIF written by QuestaSim (`power report -bsaif`) lists the nets of the
# modules, each once (in the highest module where it appears), and inside the
# std cells only the nets of their simulation models: OpenSTA's read_saif, which
# looks for the pins of the cells, finds only the top-level ports. So the
# activity is annotated net by net, on the pin that drives each net (the inputs
# of the cells then take it from the net), as Design Compiler's read_saif does:
#   - a net crossing module ports is looked up by the net that connects the
#     port in the parent module, up to the top;
#   - the pins tied to a constant get no activity and the constant as static
#     probability. Yosys writes the constants on the pins, with no tie cell (so
#     no driver pin to annotate): OpenSTA would give them its default input
#     activity (0.1 per cycle), e.g. on the test pins of the SRAMs and the
#     control pins of the pads.
#
# Input (environment):
#   XHEEP_SYNTH_OUT    synthesis output folder (netlist.v, constraints.sdc,
#                      asic_tech, asic_corner, asic_clk_period)
#   XHEEP_SAIF         SAIF of the simulation, with the header fixed for OpenSTA
#                      (see thesis_power.sh)
#   XHEEP_SAIF_SCOPE   instance of x_heep_system in the SAIF
#                      (default tb_top/testharness_i/x_heep_system_i)
#   XHEEP_POWER_RPT    report written
#   XHEEP_POWER_CSV    CSV rows written: name,opensta,<group>,internal_w,
#                      switching_w,leakage_w,total_w
#   XHEEP_POWER_NAME   netlist name in the CSV

set root [file normalize [file join [file dirname [info script]] .. .. ..]]
foreach v {XHEEP_SYNTH_OUT XHEEP_SAIF XHEEP_POWER_RPT XHEEP_POWER_CSV XHEEP_POWER_NAME} {
  if {![info exists ::env($v)] || $::env($v) eq ""} { error "\[x-heep] \$$v is not set" }
}
set out [file normalize $::env(XHEEP_SYNTH_OUT)]
set saif $::env(XHEEP_SAIF)
set scope tb_top/testharness_i/x_heep_system_i
if {[info exists ::env(XHEEP_SAIF_SCOPE)] && $::env(XHEEP_SAIF_SCOPE) ne ""} {
  set scope $::env(XHEEP_SAIF_SCOPE)
}
set top x_heep_system

proc xh_read {path} {
  set f [open $path]
  set s [string trim [read $f]]
  close $f
  return $s
}

# Libraries, netlist and constraints as in sta_reports.tcl
set tech [xh_read $out/asic_tech]
source $root/scripts/asic/tech/$tech.tcl
if {[file exists $out/asic_clk_period]} {
  set clk_period [xh_read $out/asic_clk_period]
  if {$clk_period ne ""} {
    set ::env(ASIC_CLK_PERIOD) $clk_period
  } else {
    unset -nocomplain ::env(ASIC_CLK_PERIOD)
  }
}
if {[file exists $out/asic_corner]} {
  set ::env(ASIC_CORNER) [xh_read $out/asic_corner]
}
puts "\[x-heep] library corner: [asic_corner]"
read_liberty [lindex [tech_stdcell_libs] 0]
foreach lib [tech_yosys_macro_libs] { read_liberty $lib }
read_verilog $out/netlist.v
link_design $top
read_sdc $out/constraints.sdc

# The top-level ports: OpenSTA's own reader
read_saif -scope $scope $saif

# The SAIF nets below the scope: "<instance path>/<net>" -> {T0 T1 TC}
# (the nets of the cell simulation models are skipped)
set scope_l [split $scope /]
set nscope [llength $scope_l]
set f [open $saif]
set stack {}
set dur ""
set tscale ""
set nets [dict create]
while {[gets $f line] >= 0} {
  set t [string trim $line]
  if {$t eq ""} { continue }
  if {[regexp {^\(DURATION\s+(\d+)\)} $t -> dur]} { continue }
  if {[regexp {^\(TIMESCALE\s+(.*)\)} $t -> tscale]} { continue }
  if {[regexp {^\(INSTANCE\s+(\S+)} $t -> name]} { lappend stack [string map {\\ ""} $name]; continue }
  if {$t eq "(NET" || $t eq "(PORT" || $t eq "(SAIFILE"} { lappend stack ""; continue }
  if {$t eq ")"} { set stack [lrange $stack 0 end-1]; continue }
  if {[regexp {^\((\S+)\s+\(T0 (\d+)\)\s+\(T1 (\d+)\)\s+\(TX \d+\)\s+\(TC (\d+)\)} $t -> name t0 t1 tc]} {
    if {[string match int_fwire* $name] || [string match delayed_* $name] || $name eq "notifier"} { continue }
    set path {}
    foreach s $stack { if {$s ne ""} { lappend path $s } }
    if {[lrange $path 0 [expr {$nscope - 1}]] ne $scope_l} { continue }
    dict set nets [join [concat [lrange $path $nscope end] [list [string map {\\ ""} $name]]] /] [list $t0 $t1 $tc]
  }
}
close $f
if {$dur eq "" || ![regexp {^(\d+)\s*(fs|ps|ns|us)$} [string trim $tscale] -> ts_n ts_u]} {
  error "\[x-heep] no DURATION/TIMESCALE in $saif ('$dur', '$tscale')"
}
set dur_ns [expr {$dur * $ts_n * [dict get {fs 1e-6 ps 1e-3 ns 1.0 us 1e3} $ts_u]}]
set clk [lindex [all_clocks] 0]
set per [get_property $clk period]
set ncycles [expr {$dur_ns / $per}]
puts "\[x-heep] SAIF: [dict size $nets] nets, [format %.0f $ncycles] cycles of [get_full_name $clk] ($per ns)"

# The SAIF entry of a net, also through the module ports (a port net is looked
# up again by the net that connects the port in the parent module)
set climbed 0
proc saif_lookup {key} {
  global nets climbed
  for {set i 0} {$i < 12} {incr i} {
    if {[dict exists $nets $key]} {
      if {$i > 0} { incr climbed }
      return [dict get $nets $key]
    }
    set hp ""
    foreach pat [list $key [string map {[ \\[ ] \\]} $key]] {
      if {![catch {get_pins -quiet $pat} r] && $r ne "" && $r ne "NULL"} { set hp [lindex $r 0]; break }
    }
    if {$hp eq ""} { return "" }
    if {[catch {get_nets -quiet -of_objects $hp} pn] || $pn eq "" || $pn eq "NULL"} { return "" }
    if {[catch {get_full_name [lindex $pn 0]} k2] || $k2 eq $key} { return "" }
    set key $k2
  }
  return ""
}

# The driver pins of the leaf cells
set found 0
set missing 0
set examples {}
foreach cell [get_cells -hierarchical *] {
  if {[catch {get_property $cell liberty_cell} lc] || $lc eq ""} { continue }
  if {![catch {get_property $cell is_hierarchical} h] && $h} { continue }
  foreach pin [get_pins -of_objects $cell] {
    if {[catch {get_property $pin direction} d] || $d ne "output"} { continue }
    set net [get_nets -quiet -of_objects $pin]
    if {$net eq "" || [catch {get_full_name $net} key]} { continue }
    set v [saif_lookup $key]
    if {$v ne ""} {
      lassign $v t0 t1 tc
      set duty [expr {($t0 + $t1) > 0 ? double($t1) / ($t0 + $t1) : 0.5}]
      set_power_activity -pins $pin -activity [expr {$tc / $ncycles}] -duty $duty
      incr found
    } else {
      incr missing
      if {[llength $examples] < 10} { lappend examples $key }
    }
  }
}
puts "\[x-heep] driver pins annotated from the SAIF: $found ($climbed through module ports), not found: $missing"
foreach k $examples { puts "\[x-heep]   not found: $k" }

# The pins left at the default input activity: tied to a constant (or
# undriven). Collected first, then annotated (every annotation invalidates
# the activities)
set todo {}
foreach cell [get_cells -hierarchical *] {
  if {[catch {get_property $cell liberty_cell} lc] || $lc eq ""} { continue }
  foreach pin [get_pins -of_objects $cell] {
    if {![catch {get_property $pin activity} a] && [lindex $a end] eq "input"} { lappend todo $pin }
  }
}
set nconst 0
set nother 0
foreach pin $todo {
  if {[catch {sta::pin_sim_logic_value $pin} v]} { set v X }
  if {$v eq "0" || $v eq "1"} {
    set_power_activity -pins $pin -activity 0 -duty $v
    incr nconst
  } else {
    set_power_activity -pins $pin -activity 0 -duty 0.5
    incr nother
  }
}
puts "\[x-heep] pins tied to a constant: $nconst, undriven or X: $nother (no activity)"

sta::redirect_string_begin
report_power -digits 4
set text [sta::redirect_string_end]

if {[catch {sta::version} version]} { set version "" }
set f [open $::env(XHEEP_POWER_RPT) w]
puts $f "****************************************"
puts $f "Report : power with the activity of a gate-level simulation (SAIF)"
puts $f "Design : $top"
puts $f "Tool   : OpenSTA $version"
puts $f "Date   : [clock format [clock seconds]]"
puts $f "****************************************\n"
puts $f "Netlist: $out"
puts $f "SAIF: $saif ([format %.0f $ncycles] cycles of $per ns)"
puts $f "Driver pins annotated from the SAIF: $found ($climbed through module ports), not found: $missing"
puts $f "Pins tied to a constant: $nconst, undriven or X: $nother (no activity)\n"
puts $f $text
close $f

set csv [open $::env(XHEEP_POWER_CSV) w]
set total ""
foreach line [split $text \n] {
  if {[regexp {^(Sequential|Combinational|Clock|Macro|Pad|Total)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $line -> g i s l t]} {
    puts $csv [join [list $::env(XHEEP_POWER_NAME) opensta [string tolower $g] $i $s $l $t] ,]
    if {$g eq "Total"} { set total $t }
  }
}
close $csv
if {$total eq ""} { error "\[x-heep] no Total row in the power report" }
puts "\[x-heep] power-summary cycles=[format %.0f $ncycles] annotated=$found notfound=$missing constants=$nconst opensta_mw=[format %.3f [expr {$total * 1e3}]]"
puts "\[x-heep] OpenSTA power done"
