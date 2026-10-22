#!/bin/sh
# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Power of the netlists of a synthesis campaign with the switching activity of a
# gate-level simulation (`make thesis-power`), one netlist at a time (the builds
# share build/ and implementation/synthesis/last_output):
#   1. QuestaSim runs the firmware (THESIS_POWER_APP, built first with
#      LINKER=flash_load) on the netlist and writes the activity of all the nets
#      of x_heep_system as a SAIF (power add / power report -bsaif). Pass: EXIT
#      SUCCESS. The SAIF header is fixed for OpenSTA (PROGRAM_VERSION, empty
#      DESIGN).
#   2. OpenSTA power of the netlist with that activity
#      (scripts/synthesis/opensta/saif_power.tcl), for every netlist.
#   3. Design Compiler power with the same SAIF (scripts/synthesis/dc/saif_power.tcl),
#      for the Design Compiler netlists only, as a cross-check of OpenSTA.
# The netlists are only read. The campaign folder gets
#   power.txt   netlist, PASS/FAIL, cycles, annotation, OpenSTA and DC totals, minutes
#   power.csv   netlist,engine,group,internal_w,switching_w,leakage_w,total_w
#   power/      app.log, <netlist>.{build,sim}.log, <netlist>.saif.gz,
#               <netlist>.opensta.{rpt,log}, <netlist>.dc.{rpt,log}, <netlist>.dc_saif.rpt
#
# Usage: thesis_power.sh [<campaign folder>] (default: the latest implementation/campaigns/*)
# Environment: THESIS_POWER_NETLISTS (default: every <tool>_<tech> link of the
# campaign), THESIS_POWER_APP (default hello_world), THESIS_POWER_TIMEOUT
# (default 90m per simulation), THESIS_POWER_KEEP_SAIF (default 1: keep the
# SAIF, gzipped; 0: delete it), THESIS_POWER_REUSE_SAIF (default 0; 1: analyse
# the SAIF kept by a previous run, if any, instead of simulating again; its
# firmware is then the one of that run), POSTSYNTH_MAX_CYCLES, plus QuestaSim (vsim,
# MODEL_TECH), OpenSTA (sta), Design Compiler (dc_shell, optional), PDK_XHEEP, TSMC65.

camp=${1:-$(ls -dt implementation/campaigns/*/ 2>/dev/null | head -n 1)}
camp=${camp%/}
make=${MAKE:-make}
app=${THESIS_POWER_APP:-hello_world}
tmo=${THESIS_POWER_TIMEOUT:-90m}
keep=${THESIS_POWER_KEEP_SAIF:-1}
reuse=${THESIS_POWER_REUSE_SAIF:-0}
cycles=${POSTSYNTH_MAX_CYCLES:-5000000}
scope=tb_top/testharness_i/x_heep_system_i
SYNTH_DIR=implementation/synthesis
root=$(pwd)

if [ -z "$camp" ] || [ ! -d "$camp" ]; then
  echo "ERROR: no campaign folder ('$camp'): run 'make thesis-runs' first"
  exit 1
fi
camp=$(cd "$camp" && pwd)
if ! command -v vsim >/dev/null || [ -z "$MODEL_TECH" ]; then
  echo "ERROR: QuestaSim not set up (vsim, MODEL_TECH): source its setup script first"
  exit 1
fi
if ! command -v sta >/dev/null; then
  echo "ERROR: OpenSTA (sta) not found: source its setup script first"
  exit 1
fi
dc=1
if ! command -v dc_shell >/dev/null; then
  echo "WARNING: Design Compiler (dc_shell) not found: no cross-check on the DC netlists"
  dc=0
fi
# One simulation at a time (same lock as thesis-sims)
if pgrep -u "$(id -u)" -f "[m]ake (questasim|verilator)-[a-z-]*postsynth" >/dev/null; then
  echo "ERROR: a gate-level simulation is already running:"
  pgrep -u "$(id -u)" -af "[m]ake (questasim|verilator)-[a-z-]*postsynth"
  exit 1
fi
mkdir -p build
exec 9> build/.thesis-sims.lock
if command -v flock >/dev/null && ! flock -n 9; then
  echo "ERROR: another 'make thesis-sims' or 'make thesis-power' is running"
  exit 1
fi

names=$THESIS_POWER_NETLISTS
if [ -z "$names" ]; then
  for l in "$camp"/yosys_* "$camp"/yosys-or_* "$camp"/dc_*; do
    [ -e "$l" ] && names="$names $(basename "$l")"
  done
fi
if [ -z "$names" ]; then
  echo "ERROR: no <tool>_<tech> netlist in $camp"
  exit 1
fi

pw=$camp/power
mkdir -p "$pw"
version=$(git describe --always --tags 2>/dev/null || echo unknown)
git diff --quiet HEAD -- 2>/dev/null || version="$version (modified)"
{
  echo "# $(date '+%Y-%m-%d %H:%M') thesis-power, code $version, firmware $app (flash_load), max cycles $cycles"
  echo "# $(vsim -version 2>/dev/null | head -n 1); OpenSTA $(sta -version 2>/dev/null | head -n 1)"
} | tee -a "$camp/power.txt"

echo "Firmware $app (log: $pw/app.log)"
if ! $make app PROJECT="$app" LINKER=flash_load > "$pw/app.log" 2>&1 || [ ! -f sw/build/main.hex ]; then
  echo "ERROR: firmware build failed, see $pw/app.log"
  exit 1
fi

# simulate <netlist>: QuestaSim run writing $pw/<netlist>.saif (header fixed); status 0 if passed
simulate() {
  n=$1
  $make questasim-build-postsynth > "$pw/$n.build.log" 2>&1
  bd=$(find build -maxdepth 1 -type d -name 'openhwgroup.org_systems_core-v-mini-mcu_*' | sort -V | head -n 1)
  sd=$bd/sim_postsynthesis-modelsim
  [ -d "$sd" ] || { echo "no simulation build, see $n.build.log"; return 1; }
  # The vsim command of `make questasim-run-postsynth`, with our do file
  # instead of its "run -all; quit" (and stopping, not exiting, at $finish)
  cmd=$($make -s -n -C "$sd" run PLUSARGS="c firmware=../../../sw/build/main.hex boot_sel=1 maxcycles=$cycles" \
    | grep -m1 -E '(^|[ /])vsim ')
  cmd=$(printf '%s\n' "$cmd" | sed -E "s|-do \"[^\"]*\"|-onfinish stop -do $pw/$n.saif.do|")
  case "$cmd" in *saif.do*) ;; *) echo "cannot find the vsim command of questasim-run-postsynth"; return 1;; esac
  cat > "$pw/$n.saif.do" <<EOF
power add -r -in -out -inout -internal /$scope/*
run -all
power report -all -bsaif $pw/$n.saif.raw
quit -f
EOF
  rm -f "$pw/$n.saif.raw" "$pw/$n.saif"
  (cd "$sd" && eval "timeout -k 30 $tmo $cmd") > "$pw/$n.sim.log" 2>&1
  grep -q "EXIT SUCCESS" "$pw/$n.sim.log" || { echo "simulation failed, see $n.sim.log"; return 1; }
  [ -s "$pw/$n.saif.raw" ] || { echo "no SAIF, see $n.sim.log"; return 1; }
  sed '1,12{s/(PROGRAM_VERSION /(VERSION /;s/^(DESIGN )/(DESIGN "tb_top")/}' "$pw/$n.saif.raw" > "$pw/$n.saif" \
    && rm -f "$pw/$n.saif.raw"
}

fails=0
for n in $names; do
  out=$(readlink -f "$camp/$n")
  if [ ! -f "$out/netlist_sim.v" ] || [ ! -f "$out/netlist.v" ]; then
    echo "$n MISSING (no netlist in '$out')" | tee -a "$camp/power.txt"
    fails=$((fails + 1))
    continue
  fi
  echo "==== $(date +%H:%M) $n ($(basename "$out"))"
  rm -rf "$SYNTH_DIR/last_output" && cp -R "$out" "$SYNTH_DIR/last_output"
  t0=$(date +%s)
  rm -f "$pw/$n".*.csv
  res=PASS; info=""
  if [ "$reuse" = 1 ] && [ -s "$pw/$n.saif.gz" ]; then
    gzip -dc "$pw/$n.saif.gz" > "$pw/$n.saif"
    info="(SAIF reused)"
  elif ! note=$(simulate "$n"); then
    res=FAIL; info=$note
  fi
  if [ "$res" = PASS ]; then
    XHEEP_SYNTH_OUT=$out XHEEP_SAIF=$pw/$n.saif XHEEP_SAIF_SCOPE=$scope \
      XHEEP_POWER_RPT=$pw/$n.opensta.rpt XHEEP_POWER_CSV=$pw/$n.opensta.csv XHEEP_POWER_NAME=$n \
      sta -no_init -no_splash -exit scripts/synthesis/opensta/saif_power.tcl > "$pw/$n.opensta.log" 2>&1
    if grep -q 'OpenSTA power done' "$pw/$n.opensta.log"; then
      info="$info $(sed -n 's/^\[x-heep\] power-summary //p' "$pw/$n.opensta.log")"
    else
      res=FAIL; info="$info OpenSTA failed, see $n.opensta.log"
    fi
    if [ "$dc" = 1 ] && [ "$(cat "$out/synth_tool" 2>/dev/null)" = dc ]; then
      wd=$pw/$n.dc_work
      rm -rf "$wd" && mkdir -p "$wd"
      (cd "$wd" && XHEEP_ROOT=$root XHEEP_SYNTH_OUT=$out XHEEP_SAIF=$pw/$n.saif XHEEP_SAIF_SCOPE=$scope \
        XHEEP_POWER_RPT=$pw/$n.dc.rpt XHEEP_POWER_CSV=$pw/$n.dc.csv XHEEP_POWER_NAME=$n \
        XHEEP_SAIF_COV=$pw/$n.dc_saif.rpt dc_shell -f "$root/scripts/synthesis/dc/saif_power.tcl") \
        > "$pw/$n.dc.log" 2>&1
      rm -rf "$wd"
      if grep -q 'DC power done' "$pw/$n.dc.log"; then
        cov=$(grep -m1 -E '^ *Nets ' "$pw/$n.dc_saif.rpt" | awk '{print $2}')
        info="$info $(sed -n 's/^\[x-heep\] power-summary //p' "$pw/$n.dc.log") dc_nets=$cov"
      else
        res=FAIL; info="$info; DC failed, see $n.dc.log"
      fi
    fi
  fi
  if [ -f "$pw/$n.saif" ]; then
    if [ "$keep" = 1 ]; then gzip -f "$pw/$n.saif"; else rm -f "$pw/$n.saif"; fi
  fi
  [ "$res" = PASS ] || fails=$((fails + 1))
  printf "%-22s %-4s %s, %d min\n" "$n" "$res" "$info" $(( ($(date +%s) - t0) / 60 )) | tee -a "$camp/power.txt"
done

{
  echo "netlist,engine,group,internal_w,switching_w,leakage_w,total_w"
  cat "$pw"/*.opensta.csv "$pw"/*.dc.csv 2>/dev/null
} > "$camp/power.csv"
echo "Power of $camp: $fails failed (power.txt, power.csv, reports in $pw)"
[ "$fails" -eq 0 ]
