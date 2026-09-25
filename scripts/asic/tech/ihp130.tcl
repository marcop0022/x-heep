# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# IHP-SG13G2 (ihp130) technology description for the X-HEEP ASIC flows.
#
# Input: $IHP130 = IHP Open PDK root (the directory containing libs.ref/, or
# its parent). Each resource can be overridden with the variable named in
# its asic_find call below (e.g. IHP130_STDCELL_LIB).
#
# Interface common to every scripts/asic/tech/<tech>.tcl (procs are resolved
# lazily, so sourcing this file never fails by itself):
#   TECH_NAME, TECH_ROOT_VAR     technology name, env variable of its root
#   TECH_CLK_PERIOD              default system clock period [ns] (DC)
#   TECH_DC_GATE_CLOCK           1: DC may insert integrated clock gates
#   TECH_SIM_VLOG_FLAGS          vlog flags for the simulation models
#   tech_stdcell_libs            std-cell Liberty used for mapping (yosys)
#   tech_yosys_macro_libs        Liberty of the hard cells the RTL instantiates
#   tech_lib2db_libs             Liberty files DC needs, as .db
#   tech_db_dirs                 extra directories holding .db files
#   tech_dc_target_dbs           DC target_library
#   tech_dc_link_dbs             DC link_library (without "*")
#   tech_sim_models              functional Verilog models (gate-level sim)

source [file join [file dirname [info script]] common.tcl]

set TECH_NAME ihp130
set TECH_ROOT_VAR IHP130
set TECH_CLK_PERIOD 20.0
set TECH_DC_GATE_CLOCK 0
# FUNCTIONAL: wire the SRAM macros' behavioral core to their undelayed pins
# (otherwise to A_*_DELAY nets driven only by specify-block timing checks).
set TECH_SIM_VLOG_FLAGS {+define+FUNCTIONAL}

proc _ihp130_ref {} {
  set root [asic_root IHP130 "IHP-SG13G2 PDK"]
  foreach cand [list $root/libs.ref $root/ihp-sg13g2/libs.ref] {
    if {[file isdirectory $cand]} { return $cand }
  }
  error "\[asic] \$IHP130=$root: no libs.ref/ directory under it."
}

proc tech_stdcell_libs {} {
  set ref [_ihp130_ref]
  return [asic_find "IHP std-cell Liberty" IHP130_STDCELL_LIB \
    [list $ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib]]
}

proc _ihp130_sram_libs {} {
  set ref [_ihp130_ref]
  return [asic_find "IHP SRAM Liberty" IHP130_SRAM_LIBS \
    [list "$ref/sg13g2_sram/lib/*_typ_1p20V_25C.lib"]]
}

# Optional: the IO pads are only needed as .db by DC (to link them).
proc _ihp130_io_libs {} {
  set ref [_ihp130_ref]
  set libs [asic_find "IHP IO Liberty" IHP130_IO_LIB \
    [list $ref/sg13g2_io/lib/sg13g2_io_typ_1p2V_3p3V_25C.lib "$ref/sg13g2_io/lib/sg13g2_io_typ_*.lib"] 0]
  if {[asic_env IHP130_IO_LIB] eq ""} { set libs [lrange $libs 0 0] }
  return $libs
}

# SRAM macros only: the IO pads stay black boxes in yosys (see
# ihp_sg13g2_blackbox_stubs.sv), as in the verified yosys/IHP130 flow.
proc tech_yosys_macro_libs {} { return [_ihp130_sram_libs] }

# The PDK ships Liberty only: DC needs them converted by `make asic-tech-db`.
proc tech_lib2db_libs {} {
  return [concat [tech_stdcell_libs] [_ihp130_sram_libs] [_ihp130_io_libs]]
}

proc tech_db_dirs {} { return {} }

proc tech_dc_target_dbs {} { return [asic_dbs_of ihp130 [tech_stdcell_libs]] }

proc tech_dc_link_dbs {} {
  return [concat [tech_dc_target_dbs] \
    [asic_dbs_of ihp130 [_ihp130_sram_libs]] \
    [asic_dbs_of ihp130 [_ihp130_io_libs]]]
}

proc tech_sim_models {} {
  set ref [_ihp130_ref]
  return [concat \
    [asic_find "IHP std-cell Verilog models" IHP130_STDCELL_V [list "$ref/sg13g2_stdcell/verilog/*.v"]] \
    [asic_find "IHP IO Verilog models" IHP130_IO_V [list "$ref/sg13g2_io/verilog/*.v"]] \
    [asic_find "IHP SRAM Verilog models" IHP130_SRAM_V [list "$ref/sg13g2_sram/verilog/*.v"]]]
}
