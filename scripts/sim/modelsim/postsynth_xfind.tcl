# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# X-source finder for the post-synthesis (gate-level) simulation, run by
# `make questasim-xfind-postsynth`. Simulates up to XFIND_T1, records every
# port of the netlist's hierarchical modules whose value contains X/Z, then
# advances to XFIND_T2 and records the ports that turned X/Z in between.
# Pick T1 just before and T2 just after the first X seen on a bus (e.g. with
# `make questasim-trace-postsynth`): the NEW list then holds the X path, and
# the BEFORE list the uninitialized state it may come from.
#
# Output: postsynth_xfind.txt, lines `BEFORE|NEW <time> <path> <value>`.
# Library-cell pins (all-uppercase names, e.g. A, Y, CLK, A_ADDR) are
# skipped: module ports are enough to locate the source, and far fewer.

if {![info exists XFIND_T1]} { set XFIND_T1 600ns }
if {![info exists XFIND_T2]} { set XFIND_T2 615ns }

set top /tb_top/testharness_i/x_heep_system_i/x_heep_system_synth_top_i

# Returns {path value} pairs of the signals in $sigs whose value has x/z.
proc xs_of {sigs} {
  set res {}
  set n [llength $sigs]
  for {set i 0} {$i < $n} {incr i 500} {
    set batch [lrange $sigs $i [expr {$i + 499}]]
    if {[catch {set vals [examine -radix binary {*}$batch]}]} {
      # A name examine cannot take: fall back to one signal at a time.
      set vals {}
      foreach s $batch {
        if {[catch {lappend vals [examine -radix binary $s]}]} { lappend vals "?" }
      }
    }
    foreach s $batch v $vals {
      if {[string match -nocase {*[xz]*} $v]} { lappend res $s $v }
    }
  }
  return $res
}

echo "\[postsynth_xfind] collecting module ports under $top"
set all [find signals -ports -r $top/*]
set ports {}
foreach s $all {
  if {![regexp {^[A-Z][A-Z0-9_]*$} [lindex [split $s /] end]]} { lappend ports $s }
}
echo "\[postsynth_xfind] [llength $ports] module ports (of [llength $all] ports)"

set fh [open postsynth_xfind.txt w]

run $XFIND_T1
set before [dict create]
foreach {s v} [xs_of $ports] {
  dict set before $s 1
  puts $fh "BEFORE $XFIND_T1 $s $v"
}
echo "\[postsynth_xfind] [dict size $before] X/Z ports at $XFIND_T1"

run [expr {[scan $XFIND_T2 %d] - [scan $XFIND_T1 %d]}][regsub {^[0-9.]+} $XFIND_T2 {}]
set new 0
foreach {s v} [xs_of $ports] {
  if {![dict exists $before $s]} {
    puts $fh "NEW $XFIND_T2 $s $v"
    incr new
  }
}
echo "\[postsynth_xfind] $new ports turned X/Z between $XFIND_T1 and $XFIND_T2"

close $fh
echo "\[postsynth_xfind] wrote postsynth_xfind.txt"
quit -f
