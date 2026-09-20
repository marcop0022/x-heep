#!/bin/bash
# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# pre_build hook for the `sim_postsynthesis` fusesoc target.
#
# The Yosys/IHP-SG13G2 gate-level netlist (target `asic_yosys_synthesis`,
# top module `x_heep_system`) references real PDK cell/macro module names
# (sg13g2_* standard cells and IO pads, RM_IHPSG13_1P_* SRAM macros) that are
# NOT defined anywhere in the netlist file itself: synthesis only reads their
# Liberty (.lib) timing views. QuestaSim needs their FUNCTIONAL Verilog models
# to simulate the netlist; this script locates them under $IHP130 and
# vlog-compiles them into a SEPARATE library (see PDK_LIB below), referenced
# at elaboration time via `-L` (see the `vsim_options` of the
# `sim_postsynthesis` fusesoc target in core-v-mini-mcu.core).
#
# IMPORTANT: do NOT compile these into the `work` library. The Makefile
# edalize/fusesoc generates for this target has a bare `work:` rule with no
# prerequisites; if `work/` already exists on disk (as it would if `vlog
# -work work` ran here first, since vlog auto-creates the library dir), make
# treats that target as already up to date and SKIPS the real compile step
# (`vsim -do edalize_main.tcl`, which builds the netlist/tb_top/testharness)
# entirely - `work.tb_top` then silently never exists, with no error.
#
# Adjust the CANDIDATE_GLOBS below if your PDK checkout uses a different
# layout than the one assumed here (mirrors the paths already used in
# scripts/synthesis/yosys/edalize_yosys_template.tcl for the Liberty views).

PDK_LIB=ihp_pdk_lib

set -e

if [ -z "$IHP130" ]; then
  echo "[compile_ihp_postsyn_models] ERROR: \$IHP130 is not set." >&2
  echo "  Set it to the IHP-SG13G2 PDK root (the directory containing libs.ref/, or its parent) before building sim_postsynthesis." >&2
  exit 1
fi

# Accept either the PDK root or its ihp-sg13g2/ subdirectory, like the yosys template does.
LIBS_REF=""
for cand in "$IHP130/libs.ref" "$IHP130/ihp-sg13g2/libs.ref"; do
  if [ -d "$cand" ]; then
    LIBS_REF="$cand"
    break
  fi
done

if [ -z "$LIBS_REF" ]; then
  echo "[compile_ihp_postsyn_models] ERROR: no libs.ref/ directory found under \$IHP130=$IHP130" >&2
  exit 1
fi

echo "[compile_ihp_postsyn_models] Using PDK libs.ref at: $LIBS_REF"

# Candidate globs for the functional (behavioral) Verilog views. These are
# best-effort guesses at the IHP Open PDK layout; if none match, list what IS
# there under sg13g2_stdcell / sg13g2_io / sg13g2_sram so the paths can be
# fixed here.
CANDIDATE_GLOBS=(
  "$LIBS_REF/sg13g2_stdcell/verilog/*.v"
  "$LIBS_REF/sg13g2_io/verilog/*.v"
  "$LIBS_REF/sg13g2_sram/verilog/*.v"
)

MODEL_FILES=()
for pattern in "${CANDIDATE_GLOBS[@]}"; do
  for f in $pattern; do
    [ -e "$f" ] && MODEL_FILES+=("$f")
  done
done

if [ ${#MODEL_FILES[@]} -eq 0 ]; then
  echo "[compile_ihp_postsyn_models] ERROR: no functional Verilog models found." >&2
  echo "  Tried: ${CANDIDATE_GLOBS[*]}" >&2
  echo "  Contents of $LIBS_REF:" >&2
  ls "$LIBS_REF" >&2 2>/dev/null || true
  exit 1
fi

echo "[compile_ihp_postsyn_models] Compiling ${#MODEL_FILES[@]} PDK model file(s) into library '$PDK_LIB':"
printf '  %s\n' "${MODEL_FILES[@]}"

vlib "$PDK_LIB"
vmap "$PDK_LIB" "$PDK_LIB"
vlog -work "$PDK_LIB" "${MODEL_FILES[@]}"
