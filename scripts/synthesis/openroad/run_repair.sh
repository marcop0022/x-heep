#!/bin/sh
# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# OpenROAD electrical repair of a Yosys synthesis output (`make asic-yosys-repair`):
# prep.tcl (Yosys: flat netlist with tie cells and no assign, netlist_prep.v)
# then repair.tcl (OpenROAD) on <Yosys output>, saved as a new synthesis output
# implementation/synthesis/output_yosys-or_<tech>_<date> (synth_tool yosys-or)
# with the technology, corner, clock period and constraints of the Yosys run,
# then the OpenSTA reports (run_sta.sh), as for every netlist; copied to
# implementation/synthesis/last_output.
#
# Usage: run_repair.sh <Yosys output folder>
# Environment: OPENROAD (default openroad), YOSYS (default yosys),
# XHEEP_REPAIR_TIMING=0 (no repair_timing).

in=$1
openroad=${OPENROAD:-openroad}
yosys=${YOSYS:-yosys}
SYNTH_DIR=implementation/synthesis

if [ -z "$in" ] || [ ! -f "$in/netlist.v" ] || [ "$(cat "$in/synth_tool" 2>/dev/null)" != yosys ]; then
  echo "ERROR: '$in' is not a Yosys synthesis output (netlist.v, synth_tool yosys)"
  exit 1
fi
tech=$(cat "$in/asic_tech")
out=$SYNTH_DIR/output_yosys-or_${tech}_$(date +%Y_%m_%d_%H-%M-%S)
mkdir -p "$out"
for f in asic_tech asic_corner asic_clk_period constraints.sdc; do
  cp "$in/$f" "$out/" 2>/dev/null
done
echo yosys-or > "$out/synth_tool"
basename "$in" > "$out/repair_source"
commit=$(git describe --always --tags 2>/dev/null || echo unknown)
git diff --quiet HEAD -- 2>/dev/null || commit="$commit (modified)"
echo "$commit" > "$out/git_commit"

echo "Yosys preparation of $in (log: $out/yosys_prep.log)"
XHEEP_ROOT="$(pwd)" XHEEP_SYNTH_OUT="$in" XHEEP_PREP_NETLIST="$out/netlist_prep.v" "$yosys" \
  -c scripts/synthesis/openroad/prep.tcl > "$out/yosys_prep.log" 2>&1
if [ ! -s "$out/netlist_prep.v" ] || ! grep -q "Yosys preparation done" "$out/yosys_prep.log"; then
  echo "ERROR: Yosys preparation failed, see $out/yosys_prep.log"
  tail -n 20 "$out/yosys_prep.log"
  exit 1
fi

echo "OpenROAD repair of $in into $out (log: $out/openroad.log)"
XHEEP_ROOT="$(pwd)" XHEEP_SYNTH_OUT="$in" XHEEP_REPAIR_NETLIST="$out/netlist_prep.v" XHEEP_REPAIR_OUT="$out" \
  "$openroad" -no_init -no_splash -exit scripts/synthesis/openroad/repair.tcl > "$out/openroad.log" 2>&1
if [ ! -f "$out/netlist.v" ] || ! grep -q "OpenROAD repair done" "$out/openroad.log"; then
  echo "ERROR: OpenROAD repair failed, see $out/openroad.log"
  tail -n 20 "$out/openroad.log"
  exit 1
fi
cat "$out/repair.rpt"

cp "$out/netlist.v" "$out/netlist_sim.v"
${PYTHON:-python} scripts/sim/modelsim/prefix_postsyn_netlist_modules.py "$out/netlist_sim.v" || exit 1
sh scripts/synthesis/opensta/run_sta.sh "$out"; sta_rc=$?

rm -rf "$SYNTH_DIR/last_output" && cp -R "$out" "$SYNTH_DIR/last_output"
echo "Repaired netlist and reports in $out (copied to $SYNTH_DIR/last_output)"
exit $sta_rc
