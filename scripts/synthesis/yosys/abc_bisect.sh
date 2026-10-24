#!/bin/sh
# Copyright 2026 Politecnico di Torino
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Finds the command of an ABC script that makes ABC crash or hang, on the
# temporary directory of one module kept by the Yosys flow
# (`make asic-yosys ASIC_ABC_KEEP_TMP=1`: input.blif, abc.script). Runs ABC
# on the first 1, 2, ... commands of the script and prints the exit status of
# each run: 0 ok, 139 segmentation fault, 124 timeout. Stops at the first
# failure; then runs the whole script without that command, to tell whether
# the rest of the script works.
#
# Usage: abc_bisect.sh <ABC temporary directory> [<timeout per run>, default 10m]
# Environment: YOSYS_ABC (default yosys-abc)

tmo=${2:-10m}
abc=${YOSYS_ABC:-yosys-abc}
if [ -z "$1" ] || [ ! -f "$1/abc.script" ]; then
  echo "ERROR: no abc.script in '$1'"
  exit 1
fi
dir=$(cd "$1" && pwd)
# The script names its files relative to the directory Yosys ran in (with
# -nocleanup the temporary directories are created there): run ABC from it
wd=$(dirname "$dir")

cmds=$dir/bisect.cmds
# (without the `echo + <command>` lines Yosys adds before every command)
tr ';' '\n' < "$dir/abc.script" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v -e '^$' -e '^echo ' > "$cmds"
n=$(wc -l < "$cmds")
echo "ABC script of $dir: $n commands"

# run <file with commands>: ABC on them, joined with ';'; prints the exit status
run() {
  script=$(paste -sd ';' "$1")
  (cd "$wd" && timeout -k 10 "$tmo" "$abc" -c "$script" > "$dir/bisect.log" 2>&1)
  echo $?
}

bad=0
k=1
while [ "$k" -le "$n" ]; do
  c=$(sed -n "${k}p" "$cmds")
  case "$c" in write_*) k=$((k + 1)); continue;; esac
  head -n "$k" "$cmds" > "$dir/bisect.part"
  t0=$(date +%s)
  rc=$(run "$dir/bisect.part")
  printf "%3d  %-40s exit %3s  %4d s\n" "$k" "$c" "$rc" $(( $(date +%s) - t0 ))
  if [ "$rc" -ne 0 ]; then bad=$k; break; fi
  k=$((k + 1))
done

if [ "$bad" -eq 0 ]; then
  echo "No failure: the whole script works on this module"
  exit 0
fi
echo "First failing command: $(sed -n "${bad}p" "$cmds") (exit $rc; last output in $dir/bisect.log)"
sed "${bad}d" "$cmds" | grep -v '^write_' > "$dir/bisect.part"
rc=$(run "$dir/bisect.part")
echo "Whole script without it: exit $rc"
