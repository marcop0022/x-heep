# Yosys synthesis template for the X-HEEP ASIC flows `asic_yosys_<tech>`
# (tech: ihp130 = IHP-SG13G2, tsmc65 = TSMC 65nm LP; see `make yosys-<tech>`).
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

# Target technology: asic_tech.tcl (`set ASIC_TECH <tech>`) is written in the
# build directory by the fusesoc target's `asic_tech_<tech>` pre_build hook.
# Its description (Liberty files, ...) is scripts/asic/tech/<tech>.tcl.
set ASIC_TECH ihp130
if {[file exists asic_tech.tcl]} { source asic_tech.tcl }
source ../../../scripts/asic/tech/$ASIC_TECH.tcl
puts "\[x-heep] target technology: $ASIC_TECH"

# `x_heep_system` (the actual RTL top, and the module name `$top` resolves to
# for this target) cannot be a synthesis top on its own: it exposes 6
# unconnected SystemVerilog `interface` ports (the CV-X-IF eXtension
# Interface), and slang refuses to elaborate a top-level interface port with
# nothing bound to it. The `generate_xif_tieoff_wrapper` pre_build hook
# (scripts/synthesis/yosys/generate_xif_tieoff_wrapper.py) generates
# `x_heep_system_synth_top.sv`: a thin wrapper with the exact same
# parameter/port list as `x_heep_system` minus those 6 ports (tied off
# internally instead). We synthesize THAT as top; the netlist keeps this
# name (see the bottom of this file for why it is NOT renamed back to
# `x_heep_system`).
set synth_top x_heep_system_synth_top

# Read the whole RTL through slang.
# fusesoc/edalize does not forward the `parameters` vlogdefines to a custom template,
# so the synthesis macros are (re)defined here explicitly.
read_slang --top $synth_top \
	--define-macro SYNTHESIS=true \
	--define-macro REMOVE_OBI_FIFO \
	--define-macro ASSERTS_OFF \
	--define-macro COMMON_CELLS_ASSERTS_OFF \
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
	-f "files.flist" \
	x_heep_system_synth_top.sv

# Drop the assertion cells ($check/$assert/...) slang still emits for
# unguarded immediate/concurrent assertions: they are meaningless in a gate
# netlist, and write_verilog would dump them as `assert(...)` statements,
# which the plain-Verilog postsynthesis simulation cannot compile.
yosys chformal -remove

# `--ignore-unknown-modules` above lets slang emit the not-yet-mapped PDK
# primitives (std cells, IO pads, SRAM macros instantiated by the technology
# wrappers in hw/asic/<tech>/) as black boxes, so `synth` does not error on
# their missing definitions.

# Standard-cell technology mapping is gated on the technology's kit variable
# ($TECH_ROOT_VAR: IHP130 or TSMC65, see scripts/asic/tech/<tech>.tcl).
#   - set   -> the Liberty views of the std cells and of the hard cells the RTL
#              instantiates (SRAM macros, and for tsmc65 the IO pads) are loaded,
#              and the netlist is mapped onto real library cells. Output is
#              PDK-derived: keep it private.
#   - unset -> ihp130 only: generic netlist, PDK cells (sg13g2_*, RM_IHPSG13_1P_*)
#              stay as black boxes. Safe to run / push publicly (no PDK data in
#              the output). The tsmc65 flow requires its kit.
if {[asic_env $TECH_ROOT_VAR] ne ""} {
	# Load the cell interfaces + timing before mapping. `-lib` = no netlists,
	# `-overwrite` replaces the placeholder black-box stubs read from SystemVerilog.
	set stdcell_libs [tech_stdcell_libs]
	set stdcell_lib [lindex $stdcell_libs 0]
	if {[llength $stdcell_libs] > 1} {
		puts "\[x-heep] WARNING: several std-cell Liberty files, mapping onto the first: $stdcell_lib"
	}
	puts "\[x-heep] std-cell Liberty: $stdcell_lib"
	yosys read_liberty -lib -overwrite $stdcell_lib

	# Hard cells instantiated by the RTL (blackbox, timing only).
	foreach macro_lib [tech_yosys_macro_libs] {
		puts "\[x-heep] hard-cell Liberty: $macro_lib"
		yosys read_liberty -lib -overwrite $macro_lib
	}

	yosys synth -top $synth_top
	yosys dfflibmap -liberty $stdcell_lib
	yosys abc -liberty $stdcell_lib
	yosys clean
} elseif {$ASIC_TECH eq "ihp130"} {
	puts "\[x-heep] IHP130 not set: generic synthesis, PDK cells left as black boxes."
	yosys synth -top $synth_top
} else {
	error "\[x-heep] \$$TECH_ROOT_VAR is not set: the $ASIC_TECH flow needs its design kit (see scripts/asic/tech/$ASIC_TECH.tcl)."
}

# NOTE: hierarchy is deliberately kept (no `-flatten`), like the DC flow's
# `compile_ultra -no_autoungroup`: the RTL instance paths
# (x_heep_system_i.core_v_mini_mcu_i...) survive synthesis, so the
# post-synthesis simulation can be debugged, and memories preloaded, by
# hierarchical name.
#
# The netlist's top module is `x_heep_system_synth_top`, NOT renamed
# back to `x_heep_system`. Synthesis also elaborates away all of its
# parameters, so it can no longer accept the parameter overrides
# `testharness.sv` passes when instantiating `x_heep_system` - a separate,
# simulation-only shim module (generated by `make yosys-<tech>-stage-netlist`,
# see scripts/sim/modelsim/generate_postsyn_sim_shim.py) reintroduces them
# and instantiates this netlist underneath. See the `postsynthesis-sim-shim`
# fileset in core-v-mini-mcu.core for details.

# Human-readable name for the X-HEEP ASIC flow ...
yosys write_verilog -noattr asic_x_heep_system.v

# ... and the names the edalize `yosys` backend may expect as its Make target
# (differs between edalize versions: <edam-name>.v vs <edam-name>.verilog).
yosys write_verilog -noattr $name.v
yosys write_verilog -noattr $name.verilog
