# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# TSMC 65nm LP (tsmc65) technology description for the X-HEEP ASIC flows.
# Same interface as ihp-sg13g2.tcl (see there).
#
# Input: $TSMC65 = root of the TSMC65 design kit (not in this repository).
# On the PoliTo server: TSMC65=/software/dk/tsmc65_gigi (the SRAMs are then
# found in /software/dk/tsmc65/memory/sram/generated). Libraries as in
# polheepo's DC flow (set_libs.tcl), except that the std cells are the NLDM
# view (as the IHP ones) for every tool; corner [asic_corner]
# ($ASIC_CORNER = worst: wc / ss 1.08V 125C, default; typ: tc / tt 1.2V 25C):
#   <Front_End>  = $TSMC65/Front_End, $TSMC65/digital/Front_End or $TSMC65/*/Front_End
#     std cells  <Front_End>/timing_power_noise/NLDM/tcbn65lplvt_*/tcbn65lplvt{wc,tc}.{lib,db}
#                <Front_End>/verilog/tcbn65lplvt_*/tcbn65lplvt.v
#     IO pads    <Front_End>/timing_power_noise/NLDM/tphn65lpnv2od3_sl_*/*{wcz,tc}.{lib,db}
#                (else tpdn65lpnv2od3_*)
#                <Front_End>/verilog/tphn65lpnv2od3_sl_*/*.v (else tpdn65lpnv2od3_*)
#   <SRAM>       = memory-compiler output: $TSMC65/memory/sram/generated,
#                  $TSMC65/*/memory/sram/generated or <parent of $TSMC65>/tsmc65/memory/sram/generated
#     SRAMs      Liberty *{ss*1p08*125,tt*1p2*25}*.lib under <SRAM>, .db next to it or in <SRAM>/DB
#                Verilog *ss1p08v125c.v (or any .v) under <SRAM>
# Any of them can be forced with the variable named in its asic_find call
# (TSMC65_FRONT_END, TSMC65_SRAM_DIR, TSMC65_STDCELL_LIB, TSMC65_IO_LIB,
# TSMC65_SRAM_LIBS, ...).
# The SRAM macros must match the ones instantiated by
# hw/asic/tsmc65/rtl/sram_wrapper_tsmc65.sv (TS1N65LPLL{1024,2048,4096}X32M8,
# TS1N65LPLL8192X32M16).

source [file join [file dirname [info script]] common.tcl]

set TECH_NAME tsmc65
set TECH_ROOT_VAR TSMC65

# Unit-delay-free functional simulation of the TSMC models
set TECH_SIM_VLOG_FLAGS {+define+UNIT_DELAY=0 +define+no_warning}

set TECH_ABC_DRIVING_CELL BUFFD4LVT
set TECH_ABC_LOAD_FF 6.0
set TECH_CLOCK_GATE_CELLS {CKLNQD* CKLHQD*}
# Integrated clock-gating cell inserted by Yosys and Design Compiler, as in
# polheepo (and in the clock-gate wrapper, hw/asic/tsmc65/rtl/prim_tsmc65_clk.sv)
set TECH_ICG_CELL CKLNQD16LVT
set TECH_ICG_PINS {E CP Q}
set TECH_ICG_TEST_PIN TE
# Wire-load model with zero wires, set by Design Compiler (no wire load, as OpenSTA)
set TECH_DC_ZERO_WIRE_LOAD ZeroWireload

proc _tsmc65_front_end {} {
  set root [asic_root TSMC65 "TSMC65 design kit"]
  return [lindex [asic_find "TSMC65 Front_End directory" TSMC65_FRONT_END \
    [list $root/Front_End $root/digital/Front_End "$root/*/Front_End"]] 0]
}

proc _tsmc65_sram_dir {} {
  set root [asic_root TSMC65 "TSMC65 design kit"]
  return [lindex [asic_find "TSMC65 generated SRAM directory" TSMC65_SRAM_DIR \
    [list $root/memory/sram/generated "$root/*/memory/sram/generated" \
          [file join [file dirname $root] tsmc65 memory sram generated] $root/memories $root/sram]] 0]
}

proc tech_stdcell_libs {} {
  set fe [_tsmc65_front_end]
  set c [expr {[asic_corner] eq "worst" ? "wc" : "tc"}]
  return [asic_find "TSMC65 LVT std-cell Liberty (NLDM, $c)" TSMC65_STDCELL_LIB \
    [list "$fe/timing_power_noise/NLDM/tcbn65lplvt_*/tcbn65lplvt$c.lib"]]
}

proc _tsmc65_io_libs {} {
  set fe [_tsmc65_front_end]
  if {[asic_corner] eq "worst"} {
    set pats [list "$fe/timing_power_noise/NLDM/tphn65lpnv2od3_sl_*/*wcz.lib" \
                   "$fe/timing_power_noise/NLDM/tpdn65lpnv2od3_*/tpdn65lpnv2od3wc.lib"]
  } else {
    set pats [list "$fe/timing_power_noise/NLDM/tphn65lpnv2od3_sl_*/*tc.lib" \
                   "$fe/timing_power_noise/NLDM/tpdn65lpnv2od3_*/tpdn65lpnv2od3tc.lib"]
  }
  set libs [asic_find "TSMC65 IO pad Liberty (PDUW0204CDG, [asic_corner])" TSMC65_IO_LIB $pats]
  if {[asic_env TSMC65_IO_LIB] eq ""} { set libs [lrange $libs 0 0] }
  return $libs
}

proc _tsmc65_sram_libs {} {
  set d [_tsmc65_sram_dir]
  set c [expr {[asic_corner] eq "worst" ? "ss*1p08*125" : "tt*1p2*25"}]
  return [asic_find "TSMC65 SRAM Liberty ($c)" TSMC65_SRAM_LIBS \
    [list "$d/ts1n65lpll*/SYNOPSYS/*$c*.lib" "$d/ts1n65lpll*/NLDM/*$c*.lib" \
          "$d/LIB/*$c*.lib" "$d/*/*$c*.lib"]]
}

proc tech_yosys_macro_libs {} { return [concat [_tsmc65_sram_libs] [_tsmc65_io_libs]] }

# Design Compiler: TSMC ships the .db next to the Liberty; the SRAM .db may be
# in <SRAM>/DB. `make asic-tech-db TECH=tsmc65` converts any missing one.
proc tech_lib2db_libs {} {
  return [concat [tech_stdcell_libs] [_tsmc65_sram_libs] [_tsmc65_io_libs]]
}

proc tech_db_dirs {} { return [list [file join [_tsmc65_sram_dir] DB]] }

proc tech_dc_target_dbs {} { return [asic_dbs_of tsmc65 [tech_stdcell_libs] [tech_db_dirs]] }

proc tech_dc_link_dbs {} {
  return [concat [tech_dc_target_dbs] \
    [asic_dbs_of tsmc65 [_tsmc65_sram_libs] [tech_db_dirs]] \
    [asic_dbs_of tsmc65 [_tsmc65_io_libs] [tech_db_dirs]]]
}

proc tech_sim_models {} {
  set fe [_tsmc65_front_end]
  return [concat \
    [asic_find "TSMC65 std-cell Verilog models" TSMC65_STDCELL_V \
      [list "$fe/verilog/tcbn65lplvt_*/tcbn65lplvt.v"]] \
    [tech_sim_macro_models]]
}

# The models of the non-std cells only (IO pads, SRAM macros): the Verilator
# post-synthesis simulation models the std cells from the Liberty instead.
proc tech_sim_macro_models {} {
  set fe [_tsmc65_front_end]
  set d [_tsmc65_sram_dir]
  set io_v [asic_find "TSMC65 IO pad Verilog models" TSMC65_IO_V \
    [list "$fe/verilog/tphn65lpnv2od3_sl_*/*.v" "$fe/verilog/tpdn65lpnv2od3_*/tpdn65lpnv2od3.v"]]
  if {[asic_env TSMC65_IO_V] eq ""} { set io_v [lrange $io_v 0 0] }
  return [concat $io_v \
    [asic_find "TSMC65 SRAM Verilog models" TSMC65_SRAM_V \
      [list "$d/ts1n65lpll*/VERILOG/*ss1p08v125c.v" "$d/VERILOG/*.v" "$d/ts1n65lpll*/*.v"]]]
}
