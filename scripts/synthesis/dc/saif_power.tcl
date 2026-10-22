# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Design Compiler power of a Design Compiler netlist with the switching activity
# of a gate-level simulation (`make thesis-power`, scripts/synthesis/thesis_power.sh):
# the cross-check of OpenSTA (scripts/synthesis/opensta/saif_power.tcl) with the
# same SAIF. DC cannot read the Yosys netlists (x constants, VER-720).
# Same analysis conditions as dc_script.tcl: no wire load, real loads on the
# high-fanout nets. DC's read_saif annotates the module nets of the SAIF.
#
# Input (environment): XHEEP_ROOT (repository), XHEEP_SYNTH_OUT, XHEEP_SAIF,
# XHEEP_SAIF_SCOPE, XHEEP_POWER_RPT, XHEEP_POWER_CSV, XHEEP_POWER_NAME as for
# the OpenSTA script (CSV rows: name,dc,<power group>,...), plus XHEEP_SAIF_COV
# (report_saif -hier, the annotation coverage). The row "summary" has DC's
# totals, which also count the nets of the top-level ports (in no power group).

proc xh_read {path} {
  set f [open $path]
  set s [string trim [read $f]]
  close $f
  return $s
}

# Watts of "<value> <unit>" (unit W, mW, uW, nW, pW)
proc xh_watts {value unit} {
  set k [dict get {W 1.0 mW 1e-3 uW 1e-6 nW 1e-9 pW 1e-12} $unit]
  return [expr {$value * $k}]
}

if {[catch {
  foreach v {XHEEP_ROOT XHEEP_SYNTH_OUT XHEEP_SAIF XHEEP_POWER_RPT XHEEP_POWER_CSV XHEEP_POWER_NAME XHEEP_SAIF_COV} {
    if {![info exists ::env($v)] || $::env($v) eq ""} { error "\$$v is not set" }
  }
  set out [file normalize $::env(XHEEP_SYNTH_OUT)]
  set scope tb_top/testharness_i/x_heep_system_i
  if {[info exists ::env(XHEEP_SAIF_SCOPE)] && $::env(XHEEP_SAIF_SCOPE) ne ""} {
    set scope $::env(XHEEP_SAIF_SCOPE)
  }
  set ::env(ASIC_CORNER) [xh_read $out/asic_corner]
  set p [xh_read $out/asic_clk_period]
  if {$p ne ""} { set ::env(ASIC_CLK_PERIOD) $p }
  source $::env(XHEEP_ROOT)/scripts/asic/tech/[xh_read $out/asic_tech].tcl
  set_host_options -max_cores 4
  set target_library [tech_dc_target_dbs]
  set link_library [concat "*" [tech_dc_link_dbs]]
  read_verilog -netlist $out/netlist.v
  current_design x_heep_system
  if {![link]} { error "link failed" }
  source $out/constraints.sdc
  set_app_var auto_wire_load_selection false
  set_wire_load_mode top
  set_wire_load_model -name $TECH_DC_ZERO_WIRE_LOAD
  set_app_var power_default_toggle_rate 0.1
  set_app_var power_default_static_probability 0.5
  set_app_var high_fanout_net_threshold 0
  read_saif -input $::env(XHEEP_SAIF) -instance_name $scope
  redirect $::env(XHEEP_SAIF_COV) {report_saif -hier}
  redirect -variable text {report_power -nosplit}
} err]} {
  puts "\[x-heep] ERROR: $err"
  exit 1
}

set f [open $::env(XHEEP_POWER_RPT) w]
puts $f "Power with the activity of a gate-level simulation (SAIF)"
puts $f "Netlist: $out"
puts $f "SAIF: $::env(XHEEP_SAIF)"
puts $f "Annotation coverage: [file tail $::env(XHEEP_SAIF_COV)]\n"
puts $f $text
close $f

# Units of the power-group table, then its rows and DC's totals
set dyn_unit mW
set leak_unit nW
regexp {Dynamic Power Units = 1(\S+)} $text -> dyn_unit
regexp {Leakage Power Units = 1(\S+)} $text -> leak_unit
set csv [open $::env(XHEEP_POWER_CSV) w]
set name $::env(XHEEP_POWER_NAME)
foreach line [split $text \n] {
  if {[regexp {^(io_pad|memory|black_box|clock_network|register|sequential|combinational)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $line -> g i s l t]} {
    puts $csv [join [list $name dc $g [xh_watts $i $dyn_unit] [xh_watts $s $dyn_unit] \
      [xh_watts $l $leak_unit] [xh_watts $t $dyn_unit]] ,]
  } elseif {[regexp {^Total\s+([-0-9.eE+]+) (\S+)\s+([-0-9.eE+]+) (\S+)\s+([-0-9.eE+]+) (\S+)\s+([-0-9.eE+]+) (\S+)} $line -> i iu s su l lu t tu]} {
    puts $csv [join [list $name dc total [xh_watts $i $iu] [xh_watts $s $su] [xh_watts $l $lu] [xh_watts $t $tu]] ,]
  }
}
if {![regexp {Cell Internal Power\s+=\s+(\S+) (\S+)} $text -> i iu] ||
    ![regexp {Net Switching Power\s+=\s+(\S+) (\S+)} $text -> s su] ||
    ![regexp {Cell Leakage Power\s+=\s+(\S+) (\S+)} $text -> l lu]} {
  puts "\[x-heep] ERROR: no power summary in report_power"
  exit 1
}
set i [xh_watts $i $iu]
set s [xh_watts $s $su]
set l [xh_watts $l $lu]
set t [expr {$i + $s + $l}]
puts $csv [join [list $name dc summary $i $s $l $t] ,]
close $csv
puts "\[x-heep] power-summary dc_mw=[format %.3f [expr {$t * 1e3}]]"
puts "\[x-heep] DC power done"
exit 0
