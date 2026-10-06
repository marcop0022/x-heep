# Timing constraints of the X-HEEP ASIC flows, shared by every tool so that
# all netlists are synthesized and analysed under the same constraints:
# Yosys (clock period -> ABC delay target), Design Compiler and OpenSTA.
# Plain SDC + Tcl only.

set clk_period 20.0
if {[info exists ::env(ASIC_CLK_PERIOD)] && $::env(ASIC_CLK_PERIOD) ne ""} {
  set clk_period $::env(ASIC_CLK_PERIOD)
}

create_clock -name clk_i -period $clk_period [get_ports clk_i]
