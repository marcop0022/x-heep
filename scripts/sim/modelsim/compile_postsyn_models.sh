#!/bin/bash
# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# pre_build hook for the `sim_postsynthesis` fusesoc target (run from its
# build directory).
#
# The staged post-synthesis netlist (implementation/postsynth/, see
# `make <tool>-<tech>-stage-netlist`) references library cell/macro module
# names (std cells, IO pads, SRAM macros) that are NOT defined in the netlist
# itself: synthesis only reads their timing views. QuestaSim needs their
# FUNCTIONAL Verilog models to simulate it; this script compiles the models
# of the netlist's technology (recorded by the staging step in
# implementation/postsynth/asic_tech, and located in its design kit by
# scripts/asic/tech/<tech>.tcl, queried through tclsh) into a SEPARATE
# library (see PDK_LIB below), referenced at elaboration time via `-L` (see
# the `vsim_options` of the `sim_postsynthesis` fusesoc target in
# core-v-mini-mcu.core).
#
# IMPORTANT: do NOT compile these into the `work` library. The Makefile
# edalize/fusesoc generates for this target has a bare `work:` rule with no
# prerequisites; if `work/` already exists on disk (as it would if `vlog
# -work work` ran here first, since vlog auto-creates the library dir), make
# treats that target as already up to date and SKIPS the real compile step
# (`vsim -do edalize_main.tcl`, which builds the netlist/tb_top/testharness)
# entirely - `work.tb_top` then silently never exists, with no error.
#
# The models are compiled for a zero-delay functional simulation, like the
# rest of sim_postsynthesis (whose own +nospecify +notimingcheck vlog_options
# do NOT reach this separate vlog call): without these flags the models'
# specify blocks stay active, and their placeholder path delays and
# $setuphold limits can fire spurious violations whose notifiers turn
# flops/SRAM contents into X. The technology adds its own flags (e.g.
# +define+FUNCTIONAL for the IHP SRAM macros).

PDK_LIB=pdk_lib
ROOT=../../..
TECH_FILE=$ROOT/implementation/postsynth/asic_tech
QUERY="tclsh $ROOT/scripts/asic/tech/query.tcl"

set -e

if [ ! -f "$TECH_FILE" ]; then
  echo "[compile_postsyn_models] ERROR: $TECH_FILE not found: stage a netlist first (make <tool>-<tech>-stage-netlist)." >&2
  exit 1
fi
TECH=$(cat "$TECH_FILE")
echo "[compile_postsyn_models] Staged netlist technology: $TECH"

if ! command -v tclsh >/dev/null 2>&1; then
  echo "[compile_postsyn_models] ERROR: tclsh not found (needed to read scripts/asic/tech/$TECH.tcl)." >&2
  exit 1
fi

MODELS=$($QUERY "$TECH" sim-models)
FLAGS=$($QUERY "$TECH" sim-flags)

echo "[compile_postsyn_models] Compiling into library '$PDK_LIB' (flags: $FLAGS +nospecify +notimingcheck):"
echo "$MODELS" | sed 's/^/  /'

vlib "$PDK_LIB"
vmap "$PDK_LIB" "$PDK_LIB"
# shellcheck disable=SC2086 # FLAGS and MODELS are intentionally word-split
vlog -work "$PDK_LIB" $FLAGS +nospecify +notimingcheck $MODELS
