#!/usr/bin/env python3
# Copyright EPFL contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Run by `make yosys-ihp130-stage-netlist` on the STAGED (simulation) copy of
# the Yosys netlist, in place.
#
# The netlist keeps its hierarchy (no `-flatten`, see
# edalize_yosys_template.tcl), so it defines one module per synthesized RTL
# module, mostly under their RTL names (prim_fifo_sync, tc_clk_gating,
# x_heep_system, ...). The `sim_postsynthesis` target also compiles part of
# the RTL (for testharness.sv's external device example) into the same
# library, and QuestaSim silently lets the last compiled definition of a
# module win - gate-level and RTL modules would replace each other.
# This script prefixes every module defined in the netlist (definitions and
# instantiations) with PREFIX, except the top (x_heep_system_synth_top),
# which the simulation shim instantiates by name.

import re
import sys
from pathlib import Path

NETLIST = Path(sys.argv[1] if len(sys.argv) > 1 else "implementation/yosys/netlist/x_heep_system_netlist.v")
PREFIX = "ps_"
TOP = "x_heep_system_synth_top"
# Names that must resolve to the PDK models in ihp_pdk_lib, never to a module
# of the netlist itself.
PDK_RE = re.compile(r"^\\?(sg13g2_|RM_IHPSG13)")

IDENT = r"(\\\S+|[A-Za-z_][\w$]*)"
MODULE_RE = re.compile(r"^module\s+" + IDENT)
INST_RE = re.compile(r"^(\s+)" + IDENT + r"(\s)")


def prefixed(name: str) -> str:
    if name.startswith("\\"):
        return "\\" + PREFIX + name[1:]
    return PREFIX + name


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
                 f"PDK models in ihp_pdk_lib: {', '.join(pdk[:10])}")
    if TOP not in defined:
        sys.exit(f"ERROR: top module '{TOP}' not found in {NETLIST}")

    rename = {n: prefixed(n) for n in defined if n != TOP}

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
    print(f"[prefix_postsyn_netlist_modules] {len(rename)} module(s) prefixed with '{PREFIX}' in {NETLIST}")


if __name__ == "__main__":
    main()
