#!/bin/sh
# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Synthesis campaign of the tool/technology comparison (`make thesis-runs`):
# for each technology, Yosys (with OpenSTA) and Design Compiler (then OpenSTA
# on its netlist), all with the same ASIC_CLK_PERIOD and ASIC_CORNER. The
# campaign folder implementation/campaigns/<date>_<git describe> gets:
#   runs.txt      tool, technology, status and output folder of each run
#   <tool>_<tech> link to each synthesis output (implementation/synthesis/output_*)
#   metrics.csv   scripts/synthesis/extract_metrics.tcl on the outputs
#   campaign.log  the whole log
# A failed run is recorded and the campaign goes on with the next one.
#
# Environment: THESIS_TECHS (default "ihp-sg13g2 tsmc65"), THESIS_TOOLS
# (default "yosys dc"), plus those of the flows (ASIC_CLK_PERIOD, ASIC_CORNER,
# TSMC65, ...).

techs=${THESIS_TECHS:-"ihp-sg13g2 tsmc65"}
tools=${THESIS_TOOLS:-"yosys dc"}
make=${MAKE:-make}
SYNTH_DIR=implementation/synthesis

version=$(git describe --always --tags 2>/dev/null || echo unknown)
if ! git diff --quiet HEAD -- 2>/dev/null; then
  version="$version-modified"
  echo "WARNING: tracked files have uncommitted changes: the campaign is not tied to a commit"
fi
camp=implementation/campaigns/$(date +%Y_%m_%d_%H-%M)_$version
mkdir -p "$camp"
log=$camp/campaign.log
echo "Campaign $camp: techs '$techs', tools '$tools', clk period '${ASIC_CLK_PERIOD:-SDC default}', corner '${ASIC_CORNER:-worst}'" | tee "$log"

latest() { ls -dt $SYNTH_DIR/output_$1_$2_* 2>/dev/null | head -n 1; }

outs=""
for tech in $techs; do
  for tool in $tools; do
    before=$(latest $tool $tech)
    echo "==== $(date +%H:%M) $tool $tech" | tee -a "$log"
    if [ "$tool" = dc ]; then target=asic-dc; else target=asic-yosys; fi
    $make $target TECH=$tech >> "$log" 2>&1
    rc=$?
    out=$(latest $tool $tech)
    if [ -z "$out" ] || [ "$out" = "$before" ] || [ ! -f "$out/netlist.v" ]; then
      echo "$tool $tech FAILED (rc $rc, see $log)" | tee -a "$camp/runs.txt" "$log"
      continue
    fi
    if [ "$tool" = dc ]; then
      $make asic-dc-sta SYNTH_OUT="$out" >> "$log" 2>&1 || rc=$?
    fi
    status=ok
    [ "$rc" -ne 0 ] && status="ok (rc $rc: incomplete reports, see $log)"
    echo "$tool $tech $status $out" | tee -a "$camp/runs.txt" "$log"
    ln -sfn "../../synthesis/$(basename "$out")" "$camp/${tool}_$tech"
    outs="$outs $out"
  done
done

if [ -n "$outs" ]; then
  # shellcheck disable=SC2086 # one argument per output folder
  tclsh scripts/synthesis/extract_metrics.tcl $outs > "$camp/metrics.csv" 2>> "$log" \
    && echo "Metrics in $camp/metrics.csv" | tee -a "$log" \
    || echo "ERROR: metrics extraction failed, see $log" | tee -a "$log"
fi
echo "==== $(date +%H:%M) campaign done: $camp" | tee -a "$log"
