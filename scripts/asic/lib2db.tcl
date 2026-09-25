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

if {[catch {
  source $::env(ASIC_TECH_TCL)
  set out_dir [file join $ASIC_REPO_ROOT build tech_db $TECH_NAME]
  file mkdir $out_dir

  foreach lib [tech_lib2db_libs] {
    if {[llength [asic_dbs_of $TECH_NAME [list $lib] [tech_db_dirs] 0]] > 0} {
      puts "\[lib2db] skip $lib: .db already available"
      continue
    }
    set db [file join $out_dir [file rootname [file tail $lib]].db]
    puts "\[lib2db] $lib -> $db"
    set libs [read_lib $lib -return_lib_collection]
    write_lib [get_object_name $libs] -format db -output $db
  }
} err]} {
  puts "\[lib2db] ERROR: $err"
  exit 1
}
exit 0
