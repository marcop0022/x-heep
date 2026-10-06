#!/bin/sh
# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Saves the output of an ASIC synthesis (`make asic-yosys` / `make asic-dc`)
# into implementation/synthesis/output_<tool>_<tech>_<date>, copied to
# implementation/synthesis/last_output (read by the post-synthesis simulations):
#   netlist.v, netlist_sim.v (modules prefixed for simulation), *.rpt,
#   constraints.sdc, <tool>.log, asic_tech, asic_clk_period, synth_tool
# With --sta, then runs the OpenSTA reports (scripts/synthesis/opensta/run_sta.sh).
#
# Usage: save_output.sh <yosys|dc> <tech> <fusesoc work dir> <log> [--sta]

tool=$1
tech=$2
work=$3
log=$4
sta=$5
SYNTH_DIR=implementation/synthesis

if [ -z "$work" ] || [ ! -d "$work/report" ]; then
  echo "ERROR: no $tool synthesis output (report/) in '$work', see $log"
  exit 1
fi

out=$SYNTH_DIR/output_${tool}_${tech}_$(date +%Y_%m_%d_%H-%M-%S)
mkdir -p "$out"
cp -R "$work/report/." "$out/"
cp "$log" "$out/$tool.log"
test -f "$out/netlist.v" || { echo "ERROR: synthesis failed (no netlist), see $out/$tool.log"; exit 1; }
! grep -nE '^\s*assert\s*\(' "$out/netlist.v" | head -5 | grep . || { echo "ERROR: netlist contains assert statements"; exit 1; }

echo "$tech" > "$out/asic_tech"
echo "$tool" > "$out/synth_tool"
echo "${ASIC_CLK_PERIOD:-}" > "$out/asic_clk_period"
cp "$out/netlist.v" "$out/netlist_sim.v"
${PYTHON:-python} scripts/sim/modelsim/prefix_postsyn_netlist_modules.py "$out/netlist_sim.v" || exit 1

sta_rc=0
if [ "$sta" = "--sta" ]; then
  sh scripts/synthesis/opensta/run_sta.sh "$out"; sta_rc=$?
fi

rm -rf "$SYNTH_DIR/last_output" && cp -R "$out" "$SYNTH_DIR/last_output"
echo "Synthesis ($tool, $tech): log, netlist and reports in $out (copied to $SYNTH_DIR/last_output)"
exit $sta_rc
