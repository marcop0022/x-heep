# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# TSMC 65nm LP (tsmc65) technology description for the X-HEEP ASIC flows.
# Same interface as ihp130.tcl (see there).
#
# Input: $TSMC65 = root of the TSMC65 design kit. The resources are searched
# in the usual TSMC layouts under it (the same used by polheepo):
#   <Front_End>  = $TSMC65/Front_End, $TSMC65/digital/Front_End or $TSMC65/*/Front_End
#     std cells  <Front_End>/timing_power_noise/NLDM/tcbn65lplvt_*/tcbn65lplvtwc.{lib,db}
#                <Front_End>/verilog/tcbn65lplvt_*/tcbn65lplvt.v
#     IO pads    <Front_End>/timing_power_noise/NLDM/tpdn65lpnv2od3_*/tpdn65lpnv2od3wc*.{lib,db}
#                <Front_End>/verilog/tpdn65lpnv2od3_*/tpdn65lpnv2od3.v
#   <SRAM>       = $TSMC65/memory/sram/generated (memory-compiler output), or $TSMC65/*/memory/sram/generated
#     SRAMs      <SRAM>/ts1n65lpll*/SYNOPSYS/*ss1p08v125c*.lib, .db next to it or in <SRAM>/DB
#                <SRAM>/ts1n65lpll*/VERILOG/*ss1p08v125c.v
# Any of them can be forced with the variable named in its asic_find call
# (TSMC65_FRONT_END, TSMC65_SRAM_DIR, TSMC65_STDCELL_LIB, ...).
# The SRAM macros must match the ones instantiated by
# hw/asic/tsmc65/rtl/sram_wrapper_tsmc65.sv (TS1N65LPLL{1024,2048,4096}X32M8,
# TS1N65LPLL8192X32M16).

source [file join [file dirname [info script]] common.tcl]

set TECH_NAME tsmc65
set TECH_ROOT_VAR TSMC65
set TECH_CLK_PERIOD 10.0
set TECH_DC_GATE_CLOCK 1
# As in polheepo's post-synthesis simulation of the same models.
set TECH_SIM_VLOG_FLAGS {+define+UNIT_DELAY=0 +define+no_warning}

proc _tsmc65_front_end {} {
  set root [asic_root TSMC65 "TSMC65 design kit"]
  return [lindex [asic_find "TSMC65 Front_End directory" TSMC65_FRONT_END \
    [list $root/Front_End $root/digital/Front_End "$root/*/Front_End"]] 0]
}

proc _tsmc65_sram_dir {} {
  set root [asic_root TSMC65 "TSMC65 design kit"]
  return [lindex [asic_find "TSMC65 generated SRAM directory" TSMC65_SRAM_DIR \
    [list $root/memory/sram/generated "$root/*/memory/sram/generated" $root/memories $root/sram]] 0]
}

proc tech_stdcell_libs {} {
  set fe [_tsmc65_front_end]
  return [asic_find "TSMC65 LVT std-cell Liberty (NLDM, worst corner)" TSMC65_STDCELL_LIB \
    [list "$fe/timing_power_noise/NLDM/tcbn65lplvt_*/tcbn65lplvtwc.lib"]]
}

proc _tsmc65_io_libs {} {
  set fe [_tsmc65_front_end]
  set libs [asic_find "TSMC65 IO pad Liberty (PDUW0204CDG)" TSMC65_IO_LIB \
    [list "$fe/timing_power_noise/NLDM/tpdn65lpnv2od3_*/tpdn65lpnv2od3wc.lib" \
          "$fe/timing_power_noise/NLDM/tpdn65lpnv2od3_*/tpdn65lpnv2od3wc*.lib"]]
  if {[asic_env TSMC65_IO_LIB] eq ""} { set libs [lrange $libs 0 0] }
  return $libs
}

proc _tsmc65_sram_libs {} {
  set d [_tsmc65_sram_dir]
  return [asic_find "TSMC65 SRAM Liberty (ss 1.08V 125C)" TSMC65_SRAM_LIBS \
    [list "$d/ts1n65lpll*/SYNOPSYS/*ss1p08v125c*.lib" "$d/ts1n65lpll*/NLDM/*ss1p08v125c*.lib"]]
}

proc tech_yosys_macro_libs {} {
  return [concat [_tsmc65_sram_libs] [_tsmc65_io_libs]]
}

# TSMC ships the .db next to the Liberty; the SRAM .db may be in <SRAM>/DB.
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
  set d [_tsmc65_sram_dir]
  return [concat \
    [asic_find "TSMC65 std-cell Verilog models" TSMC65_STDCELL_V \
      [list "$fe/verilog/tcbn65lplvt_*/tcbn65lplvt.v"]] \
    [asic_find "TSMC65 IO pad Verilog models" TSMC65_IO_V \
      [list "$fe/verilog/tpdn65lpnv2od3_*/tpdn65lpnv2od3.v"]] \
    [asic_find "TSMC65 SRAM Verilog models" TSMC65_SRAM_V \
      [list "$d/ts1n65lpll*/VERILOG/*ss1p08v125c.v"]]]
}
