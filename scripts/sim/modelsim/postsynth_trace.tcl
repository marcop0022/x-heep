# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Batch trace of the post-synthesis (gate-level) simulation, run by
# `make questasim-trace-postsynth`. Records, as a plain-text QuestaSim list
# (one line per time step in which any traced signal changes), the CPU's
# instruction/data OBI ports, reset/debug/sleep, and the boot/SPI flash/UART
# pins, for TRACE_TIME of simulated time, into postsynth_trace.lst.
#
# OBI ports are packed structs flattened by synthesis:
#   req (70 bit): [69] req, [68] we, [67:64] be, [63:32] addr, [31:0] wdata
#   rsp (34 bit): [33] gnt, [32] rvalid, [31:0] rdata

if {![info exists TRACE_TIME]} { set TRACE_TIME 1ms }

set M /tb_top/testharness_i/x_heep_system_i/x_heep_system_synth_top_i/x_heep_system_i/core_v_mini_mcu_i
set C $M/cpu_subsystem_i

# Add one signal to the list, skipping (with a note) any path that does not
# exist, so a single renamed port does not abort the whole trace.
proc tl {label sig} {
  if {[catch {add list -radix hex -width 12 -label $label $sig} err]} {
    echo "\[postsynth_trace] SKIPPED $label ($sig): $err"
  }
}

configure list -delta collapse
# Print values as plain hex digits (no 32'h prefix), so they fit the columns.
catch {radix -showbase 0}

tl rst_n    $C/rst_ni
tl dbg_req  $C/debug_req_i
tl sleep    $C/core_sleep_o

tl i_req    "$C/core_instr_req_o\[69\]"
tl i_addr   "$C/core_instr_req_o\[63:32\]"
tl i_gnt    "$C/core_instr_resp_i\[33\]"
tl i_rvalid "$C/core_instr_resp_i\[32\]"
tl i_rdata  "$C/core_instr_resp_i\[31:0\]"

tl d_req    "$C/core_data_req_o\[69\]"
tl d_we     "$C/core_data_req_o\[68\]"
tl d_be     "$C/core_data_req_o\[67:64\]"
tl d_addr   "$C/core_data_req_o\[63:32\]"
tl d_wdata  "$C/core_data_req_o\[31:0\]"
tl d_gnt    "$C/core_data_resp_i\[33\]"
tl d_rvalid "$C/core_data_resp_i\[32\]"
tl d_rdata  "$C/core_data_resp_i\[31:0\]"

tl boot_sel $M/boot_select_i
tl sck      $M/spi_flash_sck_o
tl csb0     $M/spi_flash_cs_0_o
tl mosi     $M/spi_flash_sd_0_o
tl miso     $M/spi_flash_sd_1_i
tl uart_tx  $M/uart_tx_o
tl exit_vld $M/exit_valid_o

echo "\[postsynth_trace] running for $TRACE_TIME"
run $TRACE_TIME
write list postsynth_trace.lst
echo "\[postsynth_trace] wrote postsynth_trace.lst"
quit -f
