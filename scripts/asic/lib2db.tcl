# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Converts the Liberty files a technology needs for Design Compiler into
# Synopsys .db, in the repository cache build/tech_db/<tech>, where
# scripts/asic/tech/common.tcl (asic_dbs_of) looks for them. Libraries that
# already have a .db (next to the .lib, or in the cache) are skipped.
# Run by `make asic-tech-db TECH=<tech>` as:
#   ASIC_TECH_TCL=<abs path of scripts/asic/tech/<tech>.tcl> lc_shell -f lib2db.tcl
# (based on polheepo's hw/asic/memories/mem_lib2db.tcl)
#
# The cells listed in TECH_LIB2DB_DROP_CELLS (tech file), which Library
# Compiler rejects and the design does not use, are removed from a copy of
# the Liberty (build/tech_db/<tech>/src/) before the conversion.

# $text without the `cell (<name>) { ... }` group of each cell in $cells
# (braces matched outside strings and comments); returns {text dropped}
proc lib_drop_cells {text cells} {
  set dropped {}
  foreach cell $cells {
    set pattern [format {cell\s*\(\s*"?%s"?\s*\)\s*\{} $cell]
    if {![regexp -indices $pattern $text m]} {
      continue
    }
    set start [lindex $m 0]
    set depth 0
    set in_str 0
    set end -1
    set n [string length $text]
    for {set i [lindex $m 1]} {$i < $n} {incr i} {
      set c [string index $text $i]
      if {$in_str} {
        if {$c eq "\\"} { incr i } elseif {$c eq "\""} { set in_str 0 }
      } elseif {$c eq "\""} {
        set in_str 1
      } elseif {$c eq "/" && [string index $text [expr {$i + 1}]] eq "*"} {
        set i [expr {[string first "*/" $text [expr {$i + 2}]] + 1}]
        if {$i <= 0} { break }
      } elseif {$c eq "\{"} {
        incr depth
      } elseif {$c eq "\}"} {
        incr depth -1
        if {$depth == 0} { set end $i; break }
      }
    }
    if {$end < 0} { error "unterminated group of cell $cell" }
    set text [string replace $text $start $end "/* cell $cell removed by lib2db.tcl */"]
    lappend dropped $cell
  }
  return [list $text $dropped]
}

if {[catch {
  source $::env(ASIC_TECH_TCL)
  set out_dir [file join $ASIC_REPO_ROOT build tech_db $TECH_NAME]
  file mkdir $out_dir
  set drop_cells [expr {[info exists TECH_LIB2DB_DROP_CELLS] ? $TECH_LIB2DB_DROP_CELLS : {}}]

  foreach lib [tech_lib2db_libs] {
    if {[llength [asic_dbs_of $TECH_NAME [list $lib] [tech_db_dirs] 0]] > 0} {
      puts "\[lib2db] skip $lib: .db already available"
      continue
    }
    set db [file join $out_dir [file rootname [file tail $lib]].db]
    puts "\[lib2db] $lib -> $db"
    set src $lib
    if {[llength $drop_cells] > 0} {
      set fh [open $lib r]
      lassign [lib_drop_cells [read $fh] $drop_cells] text dropped
      close $fh
      if {[llength $dropped] > 0} {
        file mkdir [file join $out_dir src]
        set src [file join $out_dir src [file tail $lib]]
        set fh [open $src w]
        puts -nonewline $fh $text
        close $fh
        puts "\[lib2db]   without cell(s) [join $dropped {, }]: $src"
      }
    }
    set libs [read_lib $src -return_lib_collection]
    write_lib [get_object_name $libs] -format db -output $db
  }
} err]} {
  puts "\[lib2db] ERROR: $err"
  exit 1
}
exit 0
