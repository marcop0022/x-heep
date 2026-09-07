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
# The file also defines a `synth` wrapper proc that would shadow the built-in command;
# drop it so plain `synth` still reaches the yosys built-in below.
source edalize_yosys_procs.tcl
catch {rename synth synth_edalize_unused}

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

# Generic synthesis. Standard-cell technology mapping is intentionally left out for now:
# the IHP-SG13G2 cells (sg13g2_*) and SRAM macros (RM_IHPSG13_1P_*) stay as black boxes.
# Once the Liberty files are available, add below:
#   dfflibmap -liberty <path>/sg13g2_stdcell_typ_1p20V_25C.lib
#   abc       -liberty <path>/sg13g2_stdcell_typ_1p20V_25C.lib
#   clean
synth -top $top -flatten

# Netlist under the name expected by the X-HEEP ASIC flow ...
write_verilog -noattr asic_x_heep_system.v

# ... and under the canonical name the edalize `yosys` backend expects as its build target.
write_verilog -noattr $name.v
