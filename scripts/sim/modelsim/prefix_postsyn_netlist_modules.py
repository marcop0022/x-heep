#!/usr/bin/env python3
# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Run by `make <tool>-<tech>-stage-netlist` on the STAGED (simulation) copy of
# the netlist, in place.
#
# The netlists of all ASIC flows keep their hierarchy (yosys: no `-flatten`;
# DC: -no_autoungroup), so they define one module per synthesized RTL
# module, mostly under their RTL names (prim_fifo_sync, tc_clk_gating,
# x_heep_system, ...). The `sim_postsynthesis` target also compiles part of
# the RTL (for testharness.sv's external device example) into the same
# library, and QuestaSim silently lets the last compiled definition of a
# module win - gate-level and RTL modules would replace each other.
# This script prefixes every module defined in the netlist (definitions and
# instantiations) with PREFIX, except the top (x_heep_system_synth_top),
# which the simulation shim instantiates by name.
#
# Long or escaped names (yosys-slang derives them from the full instance
# path, e.g. `\addr_dec_resp_mux$x_heep_system_synth_top.x_heep_system_i...`,
# DC appends every parameter value) become short plain identifiers,
# PREFIX + <readable base> + _<hash of the full name>: Verilator names a C++
# class and file after each module, and such names (hundreds of characters,
# each special one expanded to __0XX) exceed the file-name length limit.
# Only module names change; instance names, i.e. the hierarchical paths used
# for debugging, stay as they are.

import hashlib
import re
import sys
from pathlib import Path

NETLIST = Path(sys.argv[1] if len(sys.argv) > 1 else "implementation/postsynth/x_heep_system_netlist.v")
PREFIX = "ps_"
TOP = "x_heep_system_synth_top"
# Names that must resolve to the PDK models in pdk_lib, never to a module of
# the netlist itself (IHP cells; TSMC cell names have no common prefix to
# check, but DC/yosys never write library cells as netlist modules).
PDK_RE = re.compile(r"^\\?(sg13g2_|RM_IHPSG13)")

IDENT = r"(\\\S+|[A-Za-z_][\w$]*)"
MODULE_RE = re.compile(r"^module\s+" + IDENT)
INST_RE = re.compile(r"^(\s+)" + IDENT + r"(\s)")


MAX_PLAIN = 48  # longer (or escaped) module names get shortened
BASE_LEN = 40   # readable part kept from a shortened name


def prefixed(name: str) -> str:
    if not name.startswith("\\") and len(name) <= MAX_PLAIN:
        return PREFIX + name
    raw = name[1:] if name.startswith("\\") else name
    parts = raw.split("\\")
    if parts[0].startswith("$paramod") and len(parts) > 1:
        # yosys: $paramod$<hash>\<module> or $paramod\<module>\<P=V>...
        base = parts[1]
    else:
        # yosys-slang: <module>$<instance path>; DC: <module>_<param values>
        base = raw.split("$", 1)[0] or raw
    base = re.sub(r"\W", "_", base)[:BASE_LEN]
    digest = hashlib.sha1(name.encode()).hexdigest()[:8]
    return f"{PREFIX}{base}_{digest}"


def main() -> None:
    lines = NETLIST.read_text().splitlines(keepends=True)

    defined = set()
    for line in lines:
        m = MODULE_RE.match(line)
        if m:
            defined.add(m.group(1))

    pdk = sorted(n for n in defined if PDK_RE.match(n))
    if pdk:
        sys.exit(f"ERROR: {NETLIST} defines PDK cell modules, which would shadow the "
                 f"PDK models in pdk_lib: {', '.join(pdk[:10])}")
    if TOP not in defined:
        sys.exit(f"ERROR: top module '{TOP}' not found in {NETLIST}")

    rename = {n: prefixed(n) for n in defined if n != TOP}
    if len(set(rename.values())) != len(rename):
        sys.exit(f"ERROR: module-name collision while renaming the modules of {NETLIST}")

    out = []
    for line in lines:
        m = MODULE_RE.match(line)
        if m and m.group(1) in rename:
            line = line[:m.start(1)] + rename[m.group(1)] + line[m.end(1):]
        else:
            m = INST_RE.match(line)
            if m and m.group(2) in rename:
                line = line[:m.start(2)] + rename[m.group(2)] + line[m.end(2):]
        out.append(line)

    NETLIST.write_text("".join(out))
    shortened = sum(1 for n in rename if rename[n] != PREFIX + n)
    print(f"[prefix_postsyn_netlist_modules] {len(rename)} module(s) prefixed with '{PREFIX}' "
          f"({shortened} long/escaped name(s) shortened) in {NETLIST}")


if __name__ == "__main__":
    main()
