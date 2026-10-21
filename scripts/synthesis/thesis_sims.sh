#!/bin/sh
# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Gate-level simulation of the netlists of a synthesis campaign (`make thesis-sims`):
# the firmware (THESIS_SIM_APP, built first with LINKER=flash_load) on each
# <tool>_<tech> netlist of the campaign, one at a time (the builds share build/
# and implementation/synthesis/last_output), with QuestaSim
# (questasim-build/run-postsynth, pass: EXIT SUCCESS). If QuestaSim crashes
# (SIGSEGV: QuestaSim 2024.3 does on some flat netlists), the netlist is
# simulated with Verilator instead (verilator-build/run-postsynth, pass:
# "Program Finished with value 0"). The campaign folder gets
#   sims.txt   netlist, PASS/FAIL, simulator, minutes (one line per simulation)
#   sims/      app.log, <netlist>.<simulator>.{build,run}.log, <netlist>.uart.log
#
# Usage: thesis_sims.sh [<campaign folder>] (default: the latest implementation/campaigns/*)
# Environment: THESIS_SIM_NETLISTS (default: every <tool>_<tech> link of the
# campaign, e.g. "yosys_ihp-sg13g2 dc_tsmc65"), THESIS_SIM_APP (default
# hello_world), THESIS_SIM_TIMEOUT (default 60m per simulation),
# POSTSYNTH_MAX_CYCLES, plus QuestaSim (vsim, MODEL_TECH), Verilator, PDK_XHEEP, TSMC65.

camp=${1:-$(ls -dt implementation/campaigns/*/ 2>/dev/null | head -n 1)}
camp=${camp%/}
make=${MAKE:-make}
app=${THESIS_SIM_APP:-hello_world}
tmo=${THESIS_SIM_TIMEOUT:-60m}
SYNTH_DIR=implementation/synthesis

if [ -z "$camp" ] || [ ! -d "$camp" ]; then
  echo "ERROR: no campaign folder ('$camp'): run 'make thesis-runs' first"
  exit 1
fi
if ! command -v vsim >/dev/null || [ -z "$MODEL_TECH" ]; then
  echo "ERROR: QuestaSim not set up (vsim, MODEL_TECH): source its setup script first"
  exit 1
fi
# One simulation at a time
if pgrep -u "$(id -u)" -f "[m]ake (questasim|verilator)-[a-z-]*postsynth" >/dev/null; then
  echo "ERROR: a gate-level simulation is already running:"
  pgrep -u "$(id -u)" -af "[m]ake (questasim|verilator)-[a-z-]*postsynth"
  exit 1
fi
mkdir -p build
exec 9> build/.thesis-sims.lock
if command -v flock >/dev/null && ! flock -n 9; then
  echo "ERROR: another 'make thesis-sims' is running"
  exit 1
fi

names=$THESIS_SIM_NETLISTS
if [ -z "$names" ]; then
  for l in "$camp"/yosys_* "$camp"/yosys-or_* "$camp"/dc_*; do
    [ -e "$l" ] && names="$names $(basename "$l")"
  done
fi
if [ -z "$names" ]; then
  echo "ERROR: no <tool>_<tech> netlist in $camp"
  exit 1
fi

sims=$camp/sims
mkdir -p "$sims"
version=$(git describe --always --tags 2>/dev/null || echo unknown)
git diff --quiet HEAD -- 2>/dev/null || version="$version (modified)"
{
  echo "# $(date '+%Y-%m-%d %H:%M') thesis-sims, code $version, firmware $app (flash_load), max cycles ${POSTSYNTH_MAX_CYCLES:-default}"
  echo "# $(vsim -version 2>/dev/null | head -n 1); $(verilator --version 2>/dev/null | head -n 1)"
} | tee -a "$camp/sims.txt"

echo "Firmware $app (log: $sims/app.log)"
if ! $make app PROJECT="$app" LINKER=flash_load > "$sims/app.log" 2>&1 || [ ! -f sw/build/main.hex ]; then
  echo "ERROR: firmware build failed, see $sims/app.log"
  exit 1
fi

# simulate <netlist> <questasim|verilator>: build and run logs; status 0 if passed
simulate() {
  n=$1; s=$2
  $make "$s-build-postsynth" > "$sims/$n.$s.build.log" 2>&1
  timeout -k 30 "$tmo" $make "$s-run-postsynth" > "$sims/$n.$s.run.log" 2>&1
  bd=$(find build -maxdepth 1 -type d -name 'openhwgroup.org_systems_core-v-mini-mcu_*' | sort -V | head -n 1)
  if [ "$s" = questasim ]; then
    cp "$bd/sim_postsynthesis-modelsim/uart0.log" "$sims/$n.uart.log" 2>/dev/null
    grep -q "EXIT SUCCESS" "$sims/$n.$s.run.log"
  else
    cp "$bd/sim_postsynthesis_verilator-verilator/uart0.log" "$sims/$n.uart.log" 2>/dev/null
    grep -q "Program Finished with value 0" "$sims/$n.$s.run.log"
  fi
}

fails=0
for n in $names; do
  out=$(readlink -f "$camp/$n")
  if [ ! -f "$out/netlist_sim.v" ]; then
    echo "$n MISSING (no netlist_sim.v in '$out')" | tee -a "$camp/sims.txt"
    fails=$((fails + 1))
    continue
  fi
  echo "==== $(date +%H:%M) $n ($(basename "$out"))"
  rm -rf "$SYNTH_DIR/last_output" && cp -R "$out" "$SYNTH_DIR/last_output"
  t0=$(date +%s)
  sim=questasim; note=""
  rm -f "$sims/$n.uart.log"
  if simulate "$n" questasim; then
    res=PASS
  elif grep -qE "SIGSEGV|vsimk is exiting" "$sims/$n.questasim.run.log"; then
    note="(QuestaSim crashed, see $n.questasim.run.log)"
    sim=verilator
    if simulate "$n" verilator; then res=PASS; else res=FAIL; fi
  else
    res=FAIL
  fi
  [ "$res" = PASS ] || fails=$((fails + 1))
  printf "%-22s %-4s %-9s %4d min %s\n" "$n" "$res" "$sim" $(( ($(date +%s) - t0) / 60 )) "$note" \
    | tee -a "$camp/sims.txt"
done
echo "Simulations of $camp: $fails failed (sims.txt, logs in $sims)"
[ "$fails" -eq 0 ]
