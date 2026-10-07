# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# IHP-SG13G2 technology description for the X-HEEP ASIC flows.
#
# Input: $PDK_XHEEP = IHP Open PDK root (the directory containing libs.ref/, or
# its parent). Each resource can be overridden with the variable named in
# its asic_find call below (e.g. IHP_SG13G2_STDCELL_LIB).
#
#   TECH_NAME, TECH_ROOT_VAR     technology name, env variable of its root
#   TECH_SIM_VLOG_FLAGS          vlog flags for the simulation models
#   TECH_ABC_DRIVING_CELL        cell ABC assumes drives the inputs (only with ASIC_ABC_SIZING=1)
#   TECH_ABC_LOAD_FF             load ABC assumes on the outputs, in fF (only with ASIC_ABC_SIZING=1)
#   TECH_CLOCK_GATE_CELLS        glob patterns of the integrated clock-gating cells (STA reports)
#   TECH_ICG_CELL                integrated clock-gating cell that Yosys (clockgate)
#                                and Design Compiler (-gate_clock) insert
#   TECH_ICG_PINS                its enable, clock and gated-clock pins (Yosys clockgate)
#   TECH_ICG_TEST_PIN            its test-enable pin, tied low (Yosys clockgate)
#   tech_stdcell_libs            std-cell Liberty used for mapping (yosys)
#
# The Liberty files are those of the corner [asic_corner] ($ASIC_CORNER =
# worst: slow 1.08V 125C, default; typ: 1.2V 25C), the same for every flow.
#   tech_yosys_macro_libs        Liberty of the hard cells the RTL instantiates (SRAM, IO)
#   tech_sim_models              functional Verilog models (gate-level sim)
#   tech_sim_macro_models        the same, IO pads and SRAM macros only
#   tech_lib2db_libs             Liberty files Design Compiler needs, as .db
#   tech_db_dirs                 extra directories holding .db files
#   tech_dc_target_dbs           DC target_library
#   tech_dc_link_dbs             DC link_library (without "*")

source [file join [file dirname [info script]] common.tcl]

set TECH_NAME ihp-sg13g2
set TECH_ROOT_VAR PDK_XHEEP

# FUNCTIONAL: wire the SRAM macros' behavioral core to their undelayed pins
# (otherwise to A_*_DELAY nets driven only by specify-block timing checks).
set TECH_SIM_VLOG_FLAGS {+define+FUNCTIONAL}

set TECH_ABC_DRIVING_CELL sg13g2_buf_4
set TECH_ABC_LOAD_FF 6.0
set TECH_CLOCK_GATE_CELLS {sg13g2_lgcp_* sg13g2_slgcp_*}
# Integrated clock-gating cell inserted by Yosys and Design Compiler, the same
# the clock-gate wrapper instantiates (hw/asic/ihp-sg13g2/rtl/prim_ihp_sg13g2_clk.sv)
set TECH_ICG_CELL sg13g2_slgcp_1
set TECH_ICG_PINS {GATE CLK GCLK}
set TECH_ICG_TEST_PIN SCE

proc _ihp_sg13g2_ref {} {
  set root [asic_root PDK_XHEEP "IHP-SG13G2 PDK"]
  foreach cand [list $root/libs.ref $root/ihp-sg13g2/libs.ref] {
    if {[file isdirectory $cand]} { return $cand }
  }
  error "\[asic] \$PDK_XHEEP=$root: no libs.ref/ directory under it."
}

# Liberty file-name suffixes of the corner: std cells/SRAMs, IO pads
proc _ihp_sg13g2_corner {} {
  if {[asic_corner] eq "worst"} {
    return {slow_1p08V_125C slow_1p08V_3p0V_125C}
  }
  return {typ_1p20V_25C typ_1p2V_3p3V_25C}
}

proc tech_stdcell_libs {} {
  set ref [_ihp_sg13g2_ref]
  lassign [_ihp_sg13g2_corner] core
  return [asic_find "IHP std-cell Liberty ($core)" IHP_SG13G2_STDCELL_LIB \
    [list $ref/sg13g2_stdcell/lib/sg13g2_stdcell_$core.lib]]
}

proc _ihp_sg13g2_sram_libs {} {
  set ref [_ihp_sg13g2_ref]
  lassign [_ihp_sg13g2_corner] core
  return [asic_find "IHP SRAM Liberty ($core)" IHP_SG13G2_SRAM_LIBS \
    [list "$ref/sg13g2_sram/lib/*_$core.lib"]]
}

proc _ihp_sg13g2_io_libs {} {
  set ref [_ihp_sg13g2_ref]
  lassign [_ihp_sg13g2_corner] core io
  return [asic_find "IHP IO Liberty ($io)" IHP_SG13G2_IO_LIB \
    [list $ref/sg13g2_io/lib/sg13g2_io_$io.lib]]
}

proc tech_yosys_macro_libs {} { return [concat [_ihp_sg13g2_sram_libs] [_ihp_sg13g2_io_libs]] }

# Design Compiler: the PDK ships Liberty only, converted once to .db by
# `make asic-tech-db TECH=ihp-sg13g2` (into build/tech_db/ihp-sg13g2).
# Library Compiler rejects the analog pad of the slow IO Liberty (pad pin and
# voltage groups not defined: LBDB-206/235); X-HEEP does not use it, so it is
# left out of the .db (scripts/asic/lib2db.tcl).
set TECH_LIB2DB_DROP_CELLS {sg13g2_IOPadAnalog}
proc tech_lib2db_libs {} {
  return [concat [tech_stdcell_libs] [_ihp_sg13g2_sram_libs] [_ihp_sg13g2_io_libs]]
}

proc tech_db_dirs {} { return {} }

proc tech_dc_target_dbs {} { return [asic_dbs_of ihp-sg13g2 [tech_stdcell_libs]] }

proc tech_dc_link_dbs {} {
  return [concat [tech_dc_target_dbs] \
    [asic_dbs_of ihp-sg13g2 [_ihp_sg13g2_sram_libs]] \
    [asic_dbs_of ihp-sg13g2 [_ihp_sg13g2_io_libs]]]
}

proc tech_sim_models {} {
  set ref [_ihp_sg13g2_ref]
  return [concat \
    [asic_find "IHP std-cell Verilog models" IHP_SG13G2_STDCELL_V [list "$ref/sg13g2_stdcell/verilog/*.v"]] \
    [tech_sim_macro_models]]
}

proc tech_sim_macro_models {} {
  set ref [_ihp_sg13g2_ref]
  return [concat \
    [asic_find "IHP IO Verilog models" IHP_SG13G2_IO_V [list "$ref/sg13g2_io/verilog/*.v"]] \
    [asic_find "IHP SRAM Verilog models" IHP_SG13G2_SRAM_V [list "$ref/sg13g2_sram/verilog/*.v"]]]
}
