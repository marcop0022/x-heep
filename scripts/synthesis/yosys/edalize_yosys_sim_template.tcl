# Yosys template for the X-HEEP post-synthesis (gate-level) SIMULATION netlist.
#
# This is a sibling of `edalize_yosys_template.tcl` (the PnR flow). The key
# difference is a PARTIAL flatten: a small "spine" of modules is kept as
# hierarchy so the simulation testbench can still reach into the netlist with
# hierarchical paths (firmware backdoor into the SRAM arrays, EXIT detection on
# soc_ctrl); everything else is flattened as in the PnR flow.
#
# Invoked by the edalize `yosys` backend from the `asic_yosys_sim_netlist`
# target. The `generate_yosys_filelist` pre_build hook produces `files.flist`
# for slang, exactly as for the PnR target.
#
# Unlike the PnR template, technology mapping here is MANDATORY: a gate-level
# simulation is only meaningful against the PDK cell models, so this template
# errors out if `IHP130` is not set.

# Import the yosys-slang plugin used to elaborate the SystemVerilog sources.
yosys plugin -i slang.so

# Import yosys commands into the TCL interpreter.
yosys -import

# Echo executed commands (helps when reading the log).
echo on

# Pull in $top and $name (the edalize output basename) from the generated procs
# file. It also defines a `proc synth` that shadows the yosys `synth` command in
# the Tcl interpreter; we sidestep that by invoking every yosys pass with the
# `yosys` prefix (which goes straight to yosys' command dispatch).
source edalize_yosys_procs.tcl

# Read the whole RTL through slang (same options as the PnR template).
read_slang --top $top \
	--define-macro SYNTHESIS=true \
	--define-macro REMOVE_OBI_FIFO \
	--compat-mode \
	--keep-hierarchy \
	--allow-use-before-declare \
	--ignore-unknown-modules \
	--error-limit=100 \
	-Wno-implicit-port-type-mismatch \
	-Wno-duplicate-definition \
	-Wno-implicit-conv \
	-Wno-redef-macro \
	-Wno-unconnected-port \
	-f "files.flist"

if {!([info exists ::env(IHP130)] && $::env(IHP130) ne "")} {
	error "asic_yosys_sim_netlist requires IHP130 to point at the IHP-SG13G2 PDK\
	       (a gate-level simulation netlist is only meaningful once mapped to PDK cells)."
}

set ihp130_root $::env(IHP130)

# Locate libs.ref/ (accept either the PDK root or its ihp-sg13g2/ subdir).
set libs_ref ""
foreach cand [list $ihp130_root/libs.ref $ihp130_root/ihp-sg13g2/libs.ref] {
	if {[file isdirectory $cand]} { set libs_ref $cand; break }
}
if {$libs_ref eq ""} {
	error "IHP130 is set to '$ihp130_root' but no libs.ref/ directory was found under it."
}

set stdcell_lib $libs_ref/sg13g2_stdcell/lib/sg13g2_stdcell_typ_1p20V_25C.lib
if {![file exists $stdcell_lib]} {
	error "IHP130 std-cell Liberty not found: $stdcell_lib"
}

puts "\[x-heep] IHP130 set: reading Liberty from $libs_ref"
yosys read_liberty -lib -overwrite $stdcell_lib

# SRAM macros: read every typ-corner Liberty the PDK ships (blackbox, timing only).
foreach sram_lib [lsort [glob -nocomplain $libs_ref/sg13g2_sram/lib/*_typ_1p20V_25C.lib]] {
	puts "\[x-heep] SRAM Liberty: $sram_lib"
	yosys read_liberty -lib -overwrite $sram_lib
}

# Partial flatten: keep only the module "spine" the simulation testbench reaches
# into with hierarchical paths, and flatten everything else (CPU, DMA, crossbars,
# peripherals) into it. Full -flatten would break the testbench backdoor; full
# keep-hierarchy runs ABC once per module (hundreds of times) and is very slow.
# This keeps ~a handful of ABC runs while preserving:
#   x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i.ram*_i.<sram>       (firmware load)
#   x_heep_system_i.core_v_mini_mcu_i.ao_peripheral_subsystem_i.soc_ctrl_i.* (EXIT detect)
# Add more base names below if you need to probe/force deeper at gate level.
yosys hierarchy -top $top

# yosys-slang's --keep-hierarchy uniquifies module names as "<base>$<instance path>",
# so match the spine modules by base-name prefix. `flatten` (run by `synth -flatten`)
# skips any module carrying the keep_hierarchy attribute.
foreach spine {
	x_heep_system
	core_v_mini_mcu
	memory_subsystem
	sram_wrapper
	ao_peripheral_subsystem
	soc_ctrl
} {
	yosys setattr -mod -set keep_hierarchy 1 "$spine*"
}

yosys synth -top $top -flatten
yosys dfflibmap -liberty $stdcell_lib
yosys abc -liberty $stdcell_lib

# Gate-level simulation hygiene: drive every undriven / undefined bit to 0 so
# the netlist does not start the simulation stuck at X.
yosys setundef -zero -undriven

# Drop the power-on `init` attributes. After dfflegalize every flop is a
# resettable sg13g2_dfrbpq_1 and the testbench asserts reset, so the `1'x` init
# some RTL FSMs carry is redundant -- and it makes `clean -purge` abort with
# "Conflicting init values" as soon as those nets are tied to a constant.
yosys setattr -unset init

yosys clean -purge

# Report what came out (cell counts per module).
yosys stat -liberty $stdcell_lib

# Dedicated filename for the gate-level sim flow (does NOT overwrite the PnR
# netlist asic_x_heep_system.v).
yosys write_verilog -noattr asic_x_heep_system_sim.v

# ... and the names the edalize `yosys` backend expects as its Make target
# (differs between edalize versions: <edam-name>.v vs <edam-name>.verilog).
yosys write_verilog -noattr $name.v
yosys write_verilog -noattr $name.verilog
