# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Helpers shared by the technology descriptions (scripts/asic/tech/<tech>.tcl).
# Plain Tcl only: sourced alike by yosys, dc_shell, lc_shell and tclsh.

# Repository root (this file is scripts/asic/tech/common.tcl).
set ASIC_REPO_ROOT [file normalize [file join [file dirname [info script]] .. .. ..]]

# Value of environment variable $name, or "" if unset.
proc asic_env {name} {
  if {[info exists ::env($name)]} { return [string trim $::env($name)] }
  return ""
}

# Design-kit root taken from environment variable $var; errors if unset.
proc asic_root {var what} {
  set root [asic_env $var]
  if {$root eq ""} {
    error "\[asic] \$$var is not set: export it as the $what root."
  }
  if {![file isdirectory $root]} {
    error "\[asic] \$$var=$root is not a directory."
  }
  return [file normalize $root]
}

# Resolves a list of files: the paths in environment variable $override
# (whitespace-separated) when set, otherwise the matches of the first glob
# pattern in $patterns that matches anything. Errors when nothing is found,
# unless $required is 0 (then returns {}).
proc asic_find {what override patterns {required 1}} {
  set ov [asic_env $override]
  if {$ov ne ""} {
    set files {}
    foreach f $ov {
      if {![file exists $f]} { error "\[asic] \$$override: $f does not exist." }
      lappend files [file normalize $f]
    }
    return $files
  }
  foreach p $patterns {
    set files [lsort [glob -nocomplain -- $p]]
    if {[llength $files] > 0} { return $files }
  }
  if {$required} {
    error "\[asic] no $what found. Tried:\n  [join $patterns "\n  "]\nSet \$$override to the file(s) explicitly."
  }
  return {}
}

# The Synopsys .db of each Liberty file in $libs, looked for (in order) next
# to it, in each of $dirs, and in the repository cache build/tech_db/<tech>
# (filled by `make asic-tech-db TECH=<tech>`, which runs lc_shell). Errors on
# a missing .db unless $required is 0 (then that library is skipped).
proc asic_dbs_of {tech libs {dirs {}} {required 1}} {
  global ASIC_REPO_ROOT
  set cache [file join $ASIC_REPO_ROOT build tech_db $tech]
  set dbs {}
  foreach lib $libs {
    set stem [file rootname [file tail $lib]]
    set cands [list [file rootname $lib].db]
    foreach d [concat $dirs [list $cache]] { lappend cands [file join $d $stem.db] }
    set found ""
    foreach c $cands {
      if {[file exists $c]} { set found [file normalize $c]; break }
    }
    if {$found ne ""} {
      lappend dbs $found
    } elseif {$required} {
      error "\[asic] no .db for $lib (looked for: [join $cands {, }]). Convert it with `make asic-tech-db TECH=$tech` (runs lc_shell)."
    }
  }
  return $dbs
}
