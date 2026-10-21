# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Preparation of a Yosys netlist for the OpenROAD repair (run by run_repair.sh,
# before repair.tcl):
#
#   XHEEP_ROOT=<repository> XHEEP_SYNTH_OUT=<Yosys output> XHEEP_PREP_NETLIST=<file> \
#     yosys -c scripts/synthesis/openroad/prep.tcl
#
# OpenROAD flattens the hierarchical Yosys netlist when reading it and loses
# part of its assign statements (aliases of nets and ports: exit_value_o or the
# bus outputs end up undriven), and writes its constants as undriven nets. As
# in OpenROAD-flow-scripts, the netlist is flattened here, its constants are
# driven by tie cells (hilomap, TECH_TIE_HI/LO) and the remaining aliases by
# buffers (insbuf, TECH_BUF_CELL), so that no assign is left. All the Yosys
# cells are kept (keep), also those the flattening leaves without loads, so
# that yosys-or differs from yosys only by the repair.

foreach v {XHEEP_ROOT XHEEP_SYNTH_OUT XHEEP_PREP_NETLIST} {
  if {![info exists ::env($v)]} { error "\[x-heep] \$$v is not set" }
}
set root [file normalize $::env(XHEEP_ROOT)]
set in [file normalize $::env(XHEEP_SYNTH_OUT)]
set netlist [file normalize $::env(XHEEP_PREP_NETLIST)]

proc xh_read {path} {
  set f [open $path]
  set s [string trim [read $f]]
  close $f
  return $s
}

# Technology and corner of the synthesis
set tech [xh_read $in/asic_tech]
if {[file exists $in/asic_corner]} { set ::env(ASIC_CORNER) [xh_read $in/asic_corner] }
set here [pwd]
cd $root/scripts/asic/tech
source $tech.tcl
cd $here
puts "\[x-heep] Yosys preparation of $in ($tech, corner [asic_corner])"

foreach lib [concat [tech_stdcell_libs] [tech_yosys_macro_libs]] {
  yosys read_liberty -lib $lib
}
yosys read_verilog $in/netlist.v
yosys hierarchy -top x_heep_system
yosys flatten
yosys setattr -set keep 1 t:*
yosys splitnets
yosys opt_clean -purge
lassign [split $TECH_TIE_HI /] hi_cell hi_pin
lassign [split $TECH_TIE_LO /] lo_cell lo_pin
yosys hilomap -singleton -hicell $hi_cell $hi_pin -locell $lo_cell $lo_pin
yosys insbuf -buf {*}$TECH_BUF_CELL
yosys opt_clean -purge
yosys check
yosys stat
yosys write_verilog -noattr -noexpr -nohex -nodec $netlist
puts "\[x-heep] Yosys preparation done: $netlist"
