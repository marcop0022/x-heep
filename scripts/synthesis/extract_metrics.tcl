# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Metrics of synthesis outputs as CSV (one row per output folder), for the
# comparison of the ASIC flows (`make thesis-metrics`):
#
#   tclsh scripts/synthesis/extract_metrics.tcl <output folder>... > metrics.csv
#
# Needs the design kit of each technology (as the flows: $PDK_XHEEP, $TSMC65).
#
# - Area and cell counts are computed in the same way for every tool: the
#   cells instantiated in netlist.v, with the areas of the Liberty files of
#   the synthesis (technology and corner of the output folder), split into
#   combinational (of which buffers/inverters), sequential, integrated clock
#   gates, SRAM macros and IO pads; logic = combinational + sequential + clock
#   gates, also in gate equivalents (GE, area of TECH_NAND2_CELL). The netlists
#   are uniquified (one instance per module), so the per-module counts add up
#   to the flat ones; cells_check compares them with the tool's own count.
# - Timing and power: OpenSTA (qor/timing/power.rpt; opensta/ for DC outputs)
#   for every netlist, and Design Compiler's own reports for DC outputs.
# - Runtime and memory: from the tool log.
# Units: um^2, ns, MHz, W, s, MB.

set root [file normalize [file join [file dirname [info script]] .. ..]]

proc read_file {path} {
  set f [open $path]
  set s [read $f]
  close $f
  return $s
}
proc read_trim {path} {
  if {![file exists $path]} { return "" }
  return [string trim [read_file $path]]
}
proc num {v} {
  if {$v eq "" || ![string is double -strict $v]} { return "" }
  return [format %.10g $v]
}

# ---------------------------------------------------------------------------
# Liberty: area and class of every cell of a file (cached)
# ---------------------------------------------------------------------------
array set lib_cache {}

# Returns a dict cell -> {area class}; class: comb, bufinv, seq, icg (std
# cells), macro, pad (other libraries, by $kind)
proc lib_cells {file kind} {
  global lib_cache
  if {[info exists lib_cache($file,$kind)]} { return $lib_cache($file,$kind) }
  set text [read_file $file]
  set starts [regexp -all -indices -inline {\mcell\s*\(\s*"?([A-Za-z0-9_]+)"?\s*\)\s*\{} $text]
  set cells [dict create]
  set n [llength $starts]
  for {set i 0} {$i < $n} {incr i 2} {
    set from [lindex $starts $i 0]
    set name [string range $text {*}[lindex $starts [expr {$i + 1}]]]
    set to [expr {$i + 2 < $n ? [lindex $starts [expr {$i + 2}] 0] - 1 : [string length $text] - 1}]
    set body [string range $text $from $to]
    set area 0.0
    regexp {\marea\s*:\s*([0-9.eE+-]+)} $body -> area
    if {$kind eq "pad"} {
      set class pad
    } elseif {$kind eq "macro"} {
      set class macro
    } elseif {[regexp {clock_gating_integrated_cell} $body]} {
      set class icg
    } elseif {[regexp {\m(ff|latch|ff_bank|latch_bank|statetable)\s*\(} $body]} {
      set class seq
    } else {
      set funcs [regexp -all -inline {\mfunction\s*:\s*"([^"]*)"} $body]
      set class comb
      if {[llength $funcs] == 2 && [regexp {^[\s(!]*[A-Za-z_][A-Za-z0-9_]*[\s)']*$} [lindex $funcs 1]]} {
        set class bufinv
      }
    }
    dict set cells $name [list $area $class]
  }
  set lib_cache($file,$kind) $cells
  return $cells
}

# ---------------------------------------------------------------------------
# Netlist: number of instances of each library cell
# ---------------------------------------------------------------------------
proc netlist_counts {file cells} {
  set counts [dict create]
  set f [open $file]
  while {[gets $f line] >= 0} {
    if {![regexp {^\s+([A-Za-z_][A-Za-z0-9_]*)\s+(?:\\\S+|[A-Za-z_][^\s(]*)\s*\(} $line -> type]} { continue }
    if {[dict exists $cells $type]} { dict incr counts $type }
  }
  close $f
  return $counts
}

# ---------------------------------------------------------------------------
# Report parsers
# ---------------------------------------------------------------------------
proc first_match {text re} {
  if {[regexp -line $re $text -> v]} { return $v }
  return ""
}

# Worst slack per path group and type in an OpenSTA timing.rpt: dict "group/type" -> slack
proc sta_slacks {file} {
  set d [dict create]
  if {![file exists $file]} { return $d }
  set group ""
  set type ""
  foreach line [split [read_file $file] "\n"] {
    regexp {^Path Group: (\S+)} $line -> group
    regexp {^Path Type: (\S+)} $line -> type
    if {[regexp {^\s*(-?[0-9.]+)\s+slack \(} $line -> s]} {
      set key $group/$type
      if {![dict exists $d $key] || $s < [dict get $d $key]} { dict set d $key $s }
    }
  }
  return $d
}

# Total and per-group power of an OpenSTA power.rpt [W]
proc sta_power {file} {
  set d [dict create]
  if {![file exists $file]} { return $d }
  foreach line [split [read_file $file] "\n"] {
    if {[regexp {^(Sequential|Combinational|Clock|Macro|Pad|Total)\s+(\S+)\s+(\S+)\s+(\S+)\s+(\S+)} $line -> g i s l t]} {
      if {![dict exists $d $g]} { dict set d $g [list $i $s $l $t] }
    }
  }
  return $d
}

# Value with unit (mW, uW, nW, pW, W) to W
proc to_watt {v unit} {
  set k [dict get {W 1 mW 1e-3 uW 1e-6 nW 1e-9 pW 1e-12} $unit]
  return [expr {$v * $k}]
}

# ---------------------------------------------------------------------------
# One output folder
# ---------------------------------------------------------------------------
set columns {
  output tool tech corner clk_period_ns git_commit
  area_total area_logic area_comb area_bufinv area_seq area_icg area_sram area_pad
  logic_ge nand2_area
  cells_total cells_logic cells_comb cells_bufinv cells_seq cells_icg cells_sram cells_pad cells_check
  tool_area_total
  sta_period_min_ns sta_fmax_mhz sta_wns_setup sta_tns_setup sta_wns_hold sta_tns_hold
  sta_slack_clk_setup sta_slack_async_setup
  sta_power_total sta_power_internal sta_power_switching sta_power_leakage
  sta_power_seq sta_power_comb sta_power_clock sta_power_macro sta_power_pad
  dc_slack_setup dc_tns_setup dc_slack_hold dc_logic_levels dc_max_trans_viol dc_max_cap_viol dc_max_fanout_viol
  dc_power_total dc_power_internal dc_power_switching dc_power_leakage
  tool_cpu_s tool_wall_s tool_mem_mb
}

proc metrics {dir} {
  global root
  set m [dict create output [file tail $dir]]
  set tool [read_trim $dir/synth_tool]
  set tech [read_trim $dir/asic_tech]
  set corner [read_trim $dir/asic_corner]
  dict set m tool $tool
  dict set m tech $tech
  dict set m corner $corner
  dict set m clk_period_ns [read_trim $dir/asic_clk_period]
  dict set m git_commit [read_trim $dir/git_commit]

  # Libraries of the synthesis: technology and corner of the output folder
  if {$corner ne ""} { set ::env(ASIC_CORNER) $corner } else { unset -nocomplain ::env(ASIC_CORNER) }
  namespace eval ::tech {}
  namespace eval ::tech [list source $root/scripts/asic/tech/$tech.tcl]
  set std_lib [lindex [::tech::tech_stdcell_libs] 0]
  set io_libs [::tech::tech_io_libs]
  set cells [lib_cells $std_lib std]
  foreach lib [::tech::tech_yosys_macro_libs] {
    set kind [expr {$lib in $io_libs ? "pad" : "macro"}]
    set cells [dict merge $cells [lib_cells $lib $kind]]
  }
  set nand2 [lindex [dict get $cells $::tech::TECH_NAND2_CELL] 0]
  dict set m nand2_area [num $nand2]

  # Area and cells by class
  set area [dict create comb 0.0 bufinv 0.0 seq 0.0 icg 0.0 macro 0.0 pad 0.0]
  set count [dict create comb 0 bufinv 0 seq 0 icg 0 macro 0 pad 0]
  dict for {type n} [netlist_counts $dir/netlist.v $cells] {
    lassign [dict get $cells $type] a class
    dict set area $class [expr {[dict get $area $class] + $n * $a}]
    dict incr count $class $n
  }
  set comb [expr {[dict get $area comb] + [dict get $area bufinv]}]
  set logic [expr {$comb + [dict get $area seq] + [dict get $area icg]}]
  dict set m area_comb [num $comb]
  dict set m area_bufinv [num [dict get $area bufinv]]
  dict set m area_seq [num [dict get $area seq]]
  dict set m area_icg [num [dict get $area icg]]
  dict set m area_sram [num [dict get $area macro]]
  dict set m area_pad [num [dict get $area pad]]
  dict set m area_logic [num $logic]
  dict set m area_total [num [expr {$logic + [dict get $area macro] + [dict get $area pad]}]]
  dict set m logic_ge [num [expr {$logic / $nand2}]]
  set ncomb [expr {[dict get $count comb] + [dict get $count bufinv]}]
  set nlogic [expr {$ncomb + [dict get $count seq] + [dict get $count icg]}]
  set ntotal [expr {$nlogic + [dict get $count macro] + [dict get $count pad]}]
  dict set m cells_comb $ncomb
  dict set m cells_bufinv [dict get $count bufinv]
  dict set m cells_seq [dict get $count seq]
  dict set m cells_icg [dict get $count icg]
  dict set m cells_sram [dict get $count macro]
  dict set m cells_pad [dict get $count pad]
  dict set m cells_logic $nlogic
  dict set m cells_total $ntotal

  # OpenSTA reports (in opensta/ for a DC netlist)
  set sta $dir
  if {$tool eq "dc"} { set sta $dir/opensta }
  set qor [expr {[file exists $sta/qor.rpt] ? [read_file $sta/qor.rpt] : ""}]
  # The tool's own leaf-cell count: Yosys design hierarchy, DC qor
  set leaf ""
  if {$tool eq "yosys" && [file exists $dir/area.rpt]} {
    set leaf [first_match [read_file $dir/area.rpt] {^\s+(\d+)\s+\S+\s+x_heep_system$}]
  } elseif {[file exists $dir/qor.rpt]} {
    set leaf [first_match [read_file $dir/qor.rpt] {Leaf Cell Count:\s+(\d+)}]
  }
  dict set m cells_check [expr {$leaf eq "" ? "unknown" : ($leaf == $ntotal ? "ok" : "$tool $leaf")}]
  dict set m sta_period_min_ns [num [first_match $qor {period_min = (\S+)}]]
  dict set m sta_fmax_mhz [num [first_match $qor {fmax = (\S+)}]]
  dict set m sta_wns_setup [num [first_match $qor {^wns max (\S+)}]]
  dict set m sta_tns_setup [num [first_match $qor {^tns max (\S+)}]]
  dict set m sta_wns_hold [num [first_match $qor {^wns min (\S+)}]]
  dict set m sta_tns_hold [num [first_match $qor {^tns min (\S+)}]]
  set slacks [sta_slacks $sta/timing.rpt]
  foreach {col key} {sta_slack_clk_setup clk_i/max sta_slack_async_setup asynchronous/max} {
    dict set m $col [expr {[dict exists $slacks $key] ? [num [dict get $slacks $key]] : ""}]
  }
  set p [sta_power $sta/power.rpt]
  if {[dict exists $p Total]} {
    lassign [dict get $p Total] i s l t
    dict set m sta_power_internal [num $i]
    dict set m sta_power_switching [num $s]
    dict set m sta_power_leakage [num $l]
    dict set m sta_power_total [num $t]
  }
  foreach {col g} {sta_power_seq Sequential sta_power_comb Combinational sta_power_clock Clock sta_power_macro Macro sta_power_pad Pad} {
    if {[dict exists $p $g]} { dict set m $col [num [lindex [dict get $p $g] 3]] }
  }

  # Tool reports and log
  if {$tool eq "yosys"} {
    if {[file exists $dir/area.rpt]} {
      dict set m tool_area_total [num [first_match [read_file $dir/area.rpt] {Chip area for top module '[^']*': (\S+)}]]
    }
    if {[file exists $dir/yosys.log]
        && [regexp {CPU: user ([0-9.]+)s system ([0-9.]+)s, MEM: ([0-9.]+) MB peak} [read_file $dir/yosys.log] -> u s mem]} {
      dict set m tool_cpu_s [num [expr {$u + $s}]]
      dict set m tool_mem_mb [num $mem]
    }
  } else {
    if {[file exists $dir/area.rpt]} {
      dict set m tool_area_total [num [first_match [read_file $dir/area.rpt] {^Total cell area:\s+(\S+)}]]
    }
    if {[file exists $dir/qor.rpt]} {
      set dq [read_file $dir/qor.rpt]
      # The clk_i path group section (up to the next group or the cell counts)
      set grp ""
      regexp {Timing Path Group 'clk_i'(.*?)(?:Timing Path Group|Cell Count)} $dq -> grp
      dict set m dc_slack_setup [num [first_match $grp {Critical Path Slack:\s+(\S+)}]]
      dict set m dc_tns_setup [num [first_match $grp {Total Negative Slack:\s+(\S+)}]]
      dict set m dc_slack_hold [num [first_match $grp {Worst Hold Violation:\s+(\S+)}]]
      dict set m dc_logic_levels [num [first_match $grp {Levels of Logic:\s+(\S+)}]]
      dict set m dc_max_trans_viol [num [first_match $dq {Max Trans Violations:\s+(\S+)}]]
      dict set m dc_max_cap_viol [num [first_match $dq {Max Cap Violations:\s+(\S+)}]]
      dict set m dc_max_fanout_viol [num [first_match $dq {Max Fanout Violations:\s+(\S+)}]]
    }
    if {[file exists $dir/power.rpt]
        && [regexp -line {^Total\s+([0-9.eE+-]+) (\w+)\s+([0-9.eE+-]+) (\w+)\s+([0-9.eE+-]+) (\w+)\s+([0-9.eE+-]+) (\w+)} \
              [read_file $dir/power.rpt] -> i iu s su l lu t tu]} {
      dict set m dc_power_internal [num [to_watt $i $iu]]
      dict set m dc_power_switching [num [to_watt $s $su]]
      dict set m dc_power_leakage [num [to_watt $l $lu]]
      dict set m dc_power_total [num [to_watt $t $tu]]
    }
    set log [expr {[file exists $dir/synth.log] ? "$dir/synth.log" : "$dir/dc.log"}]
    if {[file exists $log]} {
      set lt [read_file $log]
      dict set m tool_cpu_s [num [first_match $lt {CPU usage for this session (\S+) seconds}]]
      dict set m tool_wall_s [num [first_match $lt {Elapsed time for this session (\S+) seconds}]]
      dict set m tool_mem_mb [num [first_match $lt {Memory usage for this session including child processes (\S+) Mbytes}]]
    }
  }
  return $m
}

# ---------------------------------------------------------------------------
# CSV
# ---------------------------------------------------------------------------
proc csv {v} {
  if {[regexp {[",\s]} $v]} { return "\"[string map {\" \"\"} $v]\"" }
  return $v
}

if {[llength $argv] == 0} {
  puts stderr "usage: tclsh extract_metrics.tcl <synthesis output folder>..."
  exit 2
}
puts [join $columns ,]
foreach dir $argv {
  # A campaign link: the synthesis output folder it points to
  if {[file type $dir] eq "link"} {
    set dir [file join [file dirname $dir] [file readlink $dir]]
  }
  if {[catch {metrics [file normalize $dir]} m]} {
    puts stderr "\[extract_metrics] $dir: $m"
    exit 1
  }
  set row {}
  foreach c $columns { lappend row [csv [expr {[dict exists $m $c] ? [dict get $m $c] : ""}]] }
  puts [join $row ,]
  puts stderr "\[extract_metrics] $dir: cells_check [dict get $m cells_check]"
}
