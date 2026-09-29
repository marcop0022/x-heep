// Copyright 2024 OpenHW Group
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Black-box stubs (interfaces only) of the IHP-SG13G2 cells the X-HEEP
// technology wrappers instantiate directly, for the yosys flow
// (scripts/synthesis/yosys/edalize_yosys_template.tcl):
//   - yosys-slang elaborates the RTL before any Liberty file is read, and
//     takes the ports of these cells from here;
//   - read_liberty -lib -overwrite then replaces the std cells and the SRAM
//     macros with their Liberty views; the IO pads, whose Liberty the yosys
//     flow does not read (tech_yosys_macro_libs), keep these stubs.
// The cells stay instances in the netlist. Never used in simulation (the
// PDK's own models are), nor read by Design Compiler.

// -------------------------------------------------------------------------
// Standard cells (used by prim_ihp_sg13g2_clk.sv)
// -------------------------------------------------------------------------
(* blackbox *)
module sg13g2_slgcp_1 (
    input  CLK,
    input  GATE,
    input  SCE,
    output GCLK
);
endmodule

(* blackbox *)
module sg13g2_inv_1 (
    input  A,
    output Y
);
endmodule

(* blackbox *)
module sg13g2_mux2_1 (
    input  A0,
    input  A1,
    input  S,
    output X
);
endmodule

(* blackbox *)
module sg13g2_xor2_1 (
    input  A,
    input  B,
    output X
);
endmodule

// -------------------------------------------------------------------------
// IO pad cells (used by pad_cell_*_ihp_sg13g2.sv)
// -------------------------------------------------------------------------
(* blackbox *)
module sg13g2_IOPadIn (
    inout  pad,
    output p2c
);
endmodule

(* blackbox *)
module sg13g2_IOPadOut4mA (
    inout pad,
    input c2p
);
endmodule

(* blackbox *)
module sg13g2_IOPadInOut4mA (
    inout  pad,
    input  c2p,
    input  c2p_en,
    output p2c
);
endmodule

// -------------------------------------------------------------------------
// Single-port SRAM macros (used by sram_wrapper_ihp_sg13g2.sv)
// -------------------------------------------------------------------------
(* blackbox *)
module RM_IHPSG13_1P_256x32_c2_bm_bist (
    input         A_CLK,
    input         A_MEN,
    input         A_WEN,
    input         A_REN,
    input  [ 7:0] A_ADDR,
    input  [31:0] A_DIN,
    input         A_DLY,
    output [31:0] A_DOUT,
    input  [31:0] A_BM,
    input         A_BIST_CLK,
    input         A_BIST_EN,
    input         A_BIST_MEN,
    input         A_BIST_WEN,
    input         A_BIST_REN,
    input  [ 7:0] A_BIST_ADDR,
    input  [31:0] A_BIST_DIN,
    input  [31:0] A_BIST_BM
);
endmodule

(* blackbox *)
module RM_IHPSG13_1P_512x32_c2_bm_bist (
    input         A_CLK,
    input         A_MEN,
    input         A_WEN,
    input         A_REN,
    input  [ 8:0] A_ADDR,
    input  [31:0] A_DIN,
    input         A_DLY,
    output [31:0] A_DOUT,
    input  [31:0] A_BM,
    input         A_BIST_CLK,
    input         A_BIST_EN,
    input         A_BIST_MEN,
    input         A_BIST_WEN,
    input         A_BIST_REN,
    input  [ 8:0] A_BIST_ADDR,
    input  [31:0] A_BIST_DIN,
    input  [31:0] A_BIST_BM
);
endmodule

(* blackbox *)
module RM_IHPSG13_1P_1024x32_c2_bm_bist (
    input         A_CLK,
    input         A_MEN,
    input         A_WEN,
    input         A_REN,
    input  [ 9:0] A_ADDR,
    input  [31:0] A_DIN,
    input         A_DLY,
    output [31:0] A_DOUT,
    input  [31:0] A_BM,
    input         A_BIST_CLK,
    input         A_BIST_EN,
    input         A_BIST_MEN,
    input         A_BIST_WEN,
    input         A_BIST_REN,
    input  [ 9:0] A_BIST_ADDR,
    input  [31:0] A_BIST_DIN,
    input  [31:0] A_BIST_BM
);
endmodule

// The 4096- and 8192-word banks are built from these 2048x32 macros in
// sram_wrapper_ihp_sg13g2.sv (no 4096x32 cut; the 8192x32 one has no byte mask).
(* blackbox *)
module RM_IHPSG13_1P_2048x32_c2_bm_bist (
    input         A_CLK,
    input         A_MEN,
    input         A_WEN,
    input         A_REN,
    input  [10:0] A_ADDR,
    input  [31:0] A_DIN,
    input         A_DLY,
    output [31:0] A_DOUT,
    input  [31:0] A_BM,
    input         A_BIST_CLK,
    input         A_BIST_EN,
    input         A_BIST_MEN,
    input         A_BIST_WEN,
    input         A_BIST_REN,
    input  [10:0] A_BIST_ADDR,
    input  [31:0] A_BIST_DIN,
    input  [31:0] A_BIST_BM
);
endmodule
