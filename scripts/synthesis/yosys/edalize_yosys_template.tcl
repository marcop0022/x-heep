# Yosys synthesis template for the X-HEEP standalone ASIC flow (IHP-SG13G2 target).
#
# Invoked by the edalize `yosys` backend as: yosys -p 'tcl edalize_yosys_template.tcl'
# Because a custom `yosys_template` is set in core-v-mini-mcu.core, edalize does NOT
# generate its own `edalize_yosys_template.tcl`; it only generates `edalize_yosys_procs.tcl`,
# from which `generate_yosys_filelist.sh` (pre_build hook) produces `files.flist` for slang.

# Import the yosys-slang plugin used to elaborate the SystemVerilog sources.
yosys plugin -i slang.so

# Import yosys commands into the TCL interpreter.
yosys -import

# Echo executed commands (helps when reading yosys.log).
echo on

# Pull in $top and $name (the edalize output basename) from the generated procs file.
# It also defines a `proc synth` that shadows the yosys `synth` command in the Tcl
# interpreter; we sidestep that by invoking every yosys pass with the `yosys` prefix
# (which goes straight to yosys' command dispatch, not the Tcl proc).
source edalize_yosys_procs.tcl

# Read the whole RTL through slang.
# fusesoc/edalize does not forward the `parameters` vlogdefines to a custom template,
# so the synthesis macros are (re)defined here explicitly.
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

# `--ignore-unknown-modules` above lets slang emit the not-yet-mapped PDK
# primitives (sg13g2_* std cells / IO pads, RM_IHPSG13_1P_* SRAM macros) as
# black boxes, so `synth` does not error on their missing definitions.

# Standard-cell technology mapping is gated on the `IHP130` environment variable.
#   - IHP130 set  -> it must point to the IHP-SG13G2 PDK root (the directory that
#                    contains `libs.ref/`, or its parent). The Liberty views of the
#                    std cells and SRAM macros are loaded, and the netlist is mapped
#                    onto real sg13g2_* cells. Output is PDK-derived: keep it private.
#   - IHP130 unset -> generic netlist, PDK cells (sg13g2_*, RM_IHPSG13_1P_*) stay as
#                    black boxes. Safe to run / push publicly (no PDK data in the output).
if {[info exists ::env(IHP130)] && $::env(IHP130) ne ""} {
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

	# Load the cell interfaces + timing before mapping. `-lib` = no netlists,
	# `-overwrite` replaces the placeholder black-box stubs read from SystemVerilog.
	puts "\[x-heep] IHP130 set: reading Liberty from $libs_ref"
	yosys read_liberty -lib -overwrite $stdcell_lib

	# SRAM macros: read every typ-corner Liberty the PDK ships (blackbox, timing only).
	foreach sram_lib [lsort [glob -nocomplain $libs_ref/sg13g2_sram/lib/*_typ_1p20V_25C.lib]] {
		puts "\[x-heep] SRAM Liberty: $sram_lib"
		yosys read_liberty -lib -overwrite $sram_lib
	}

	yosys synth -top $top -flatten
	yosys dfflibmap -liberty $stdcell_lib
	yosys abc -liberty $stdcell_lib
	yosys clean
} else {
	puts "\[x-heep] IHP130 not set: generic synthesis, PDK cells left as black boxes."
	yosys synth -top $top -flatten
}

# Human-readable name for the X-HEEP ASIC flow ...
yosys write_verilog -noattr asic_x_heep_system.v

# ... and the names the edalize `yosys` backend may expect as its Make target
# (differs between edalize versions: <edam-name>.v vs <edam-name>.verilog).
yosys write_verilog -noattr $name.v
yosys write_verilog -noattr $name.verilog
