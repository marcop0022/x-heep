#!/bin/sh
# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# OpenSTA reports of a synthesis output folder (sta_reports.tcl).
# Usage: run_sta.sh <synthesis output folder> [<report folder>]
# The reports go to the output folder itself for a Yosys netlist, to its
# opensta/ folder for a Design Compiler one (whose own reports have the same
# names), or to <report folder> if given.

out=$1
rpt=$2
if [ -z "$rpt" ]; then
	rpt=$out
	if [ "$(cat "$out/synth_tool" 2>/dev/null)" = dc ]; then
		rpt=$out/opensta
	fi
fi

if ! command -v sta >/dev/null 2>&1; then
	echo "WARNING: OpenSTA (sta) not found: no timing, power, ... reports."
	exit 0
fi

mkdir -p "$rpt"
echo "Running OpenSTA on $out, reports and log in $rpt"
XHEEP_SYNTH_OUT="$out" XHEEP_STA_REPORTS="$rpt" sta -no_init -no_splash -exit "$(dirname "$0")/sta_reports.tcl" > "$rpt/sta.log" 2>&1
if ! grep -q 'OpenSTA reports done' "$rpt/sta.log"; then
	echo "ERROR: OpenSTA failed, see $rpt/sta.log"
	tail -n 20 "$rpt/sta.log"
	exit 1
fi
# Reports in which an OpenSTA command failed (sta_reports.tcl goes on)
if grep '^\[x-heep\] ERROR' "$rpt/sta.log"; then
	echo "ERROR: some OpenSTA reports are incomplete, see $rpt/sta.log"
	exit 1
fi
