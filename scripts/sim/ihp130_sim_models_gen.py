#!/usr/bin/env python3
# Copyright 2026 Politecnico di Torino.
# Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
# SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
#
# FuseSoC generator: emit a .core listing the IHP-SG13G2 PDK Verilog cell and
# SRAM-macro models needed to run the X-HEEP post-synthesis (gate-level)
# simulation. The models live under $IHP130 (outside the repo), so they cannot
# be referenced by a static fileset -- this generator resolves them at setup
# time and writes a .core with absolute paths.
#
# Invoked by FuseSoC with a single argument: the path to a YAML config file
# carrying `vlnv`, `files_root` and the `parameters` from the `generate:` block.
# The `verilog_models` parameter lists the model files relative to
# `$IHP130/.../libs.ref`, in compilation order.

import os
import sys

import yaml


def die(msg):
    print(f"ERROR [ihp130_sim_models_gen]: {msg}", file=sys.stderr)
    sys.exit(1)


def find_libs_ref(ihp130):
    for cand in (
        os.path.join(ihp130, "libs.ref"),
        os.path.join(ihp130, "ihp-sg13g2", "libs.ref"),
    ):
        if os.path.isdir(cand):
            return cand
    die(f"no libs.ref/ directory found under IHP130='{ihp130}'")


def main():
    if len(sys.argv) != 2:
        die(f"usage: {sys.argv[0]} <config.yaml>")

    with open(sys.argv[1]) as f:
        cfg = yaml.safe_load(f)

    vlnv = cfg["vlnv"]
    core_name = vlnv.split(":")[2]
    rel_models = cfg.get("parameters", {}).get("verilog_models") or []
    if not rel_models:
        die("the generate: block must pass a non-empty 'verilog_models' list")

    ihp130 = os.environ.get("IHP130", "").strip()
    if not ihp130:
        die(
            "IHP130 is not set. Point it at the IHP-SG13G2 PDK to build the "
            "post-synthesis simulation (the same variable as `make yosys-ihp130-sim`)."
        )

    libs_ref = find_libs_ref(ihp130)

    files = []
    for rel in rel_models:
        path = os.path.normpath(os.path.join(libs_ref, rel))
        if not os.path.isfile(path):
            die(f"PDK Verilog model not found: {path}")
        files.append(path)

    core = {
        "name": vlnv,
        "description": (
            "IHP-SG13G2 PDK Verilog models for X-HEEP post-synthesis simulation "
            f"(resolved from IHP130={ihp130})"
        ),
        "filesets": {
            "pdk_sim_models": {"files": files, "file_type": "verilogSource"},
        },
        "targets": {
            "default": {"filesets": ["pdk_sim_models"]},
        },
    }

    out = f"{core_name}.core"
    with open(out, "w") as f:
        f.write("CAPI=2:\n")
        yaml.safe_dump(core, f, sort_keys=False)

    print(f"[ihp130_sim_models_gen] wrote {out} with {len(files)} PDK model(s):")
    for p in files:
        print(f"    {p}")


if __name__ == "__main__":
    main()
