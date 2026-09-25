// Copyright 2022 OpenHW Group
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// TSMC 65nm LP clock primitives (tcbn65lplvt library), mapping the same
// generic clock modules as hw/asic/ihp-sg13g2/rtl/cells/prim_ihp_sg13g2_clk.sv.
// Cells as in polheepo (hw/asic/rtl/prim_tsmc65_clk.sv).

// Primitives
module tsmc65_clk_gating (
  input  logic clk_i,
  input  logic en_i,
  input  logic test_en_i,
  output logic clk_o
);

  (* keep *)
  CKLNQD16LVT clk_gate_inst (
    .TE(test_en_i),
    .CP(clk_i),
    .E (en_i),
    .Q (clk_o)
  );

endmodule

module tsmc65_clk_inverter (
  input  logic clk_i,
  output logic clk_o
);

  (* keep *)
  CKND16LVT clk_inv_inst (
    .I (clk_i),
    .ZN(clk_o)
  );

endmodule

module tsmc65_clk_mux2 (
  input  logic clk0_i,
  input  logic clk1_i,
  input  logic clk_sel_i,
  output logic clk_o
);

  (* keep *)
  CKMUX2D4LVT clk_mux2_inst (
    .I0(clk0_i),
    .I1(clk1_i),
    .S (clk_sel_i),
    .Z (clk_o)
  );

endmodule

module tsmc65_clk_xor2 (
  input  logic clk0_i,
  input  logic clk1_i,
  output logic clk_o
);

  (* keep *)
  CKXOR2D4LVT clk_xor2_inst (
    .A1(clk0_i),
    .A2(clk1_i),
    .Z (clk_o)
  );

endmodule

// Cluster
module cluster_clock_inverter (
  input  logic clk_i,
  output logic clk_o
);

  tsmc65_clk_inverter clk_inv_inst (.*);

endmodule

// Pulp
module pulp_clock_mux2 (
  input  logic clk0_i,
  input  logic clk1_i,
  input  logic clk_sel_i,
  output logic clk_o
);

  tsmc65_clk_mux2 clk_mux2_inst (.*);

endmodule

module pulp_clock_inverter (
  input  logic clk_i,
  output logic clk_o
);

  tsmc65_clk_inverter clk_inv_inst (.*);

endmodule

// OpenHW
module cv32e40p_clock_gate (
  input  logic clk_i,
  input  logic en_i,
  input  logic scan_cg_en_i,
  output logic clk_o
);

  tsmc65_clk_gating clk_gate_inst (
    .clk_i,
    .en_i,
    .test_en_i(scan_cg_en_i),
    .clk_o
  );

endmodule

module cve2_clock_gate (
  input  logic clk_i,
  input  logic en_i,
  input  logic scan_cg_en_i,
  output logic clk_o
);

  tsmc65_clk_gating clk_gate_inst (
    .clk_i,
    .en_i,
    .test_en_i(scan_cg_en_i),
    .clk_o
  );

endmodule

// TC
module tc_clk_gating #(
    parameter bit IS_FUNCTIONAL = 1'b1
) (
    input  logic clk_i,
    input  logic en_i,
    input  logic test_en_i,
    output logic clk_o
);

  tsmc65_clk_gating clk_gate_inst (.*);

endmodule

module tc_clk_xor2 (
  input  logic clk0_i,
  input  logic clk1_i,
  output logic clk_o
);

  tsmc65_clk_xor2 clk_xor2_inst (.*);

endmodule

module tc_clk_mux2 (
  input  logic clk0_i,
  input  logic clk1_i,
  input  logic clk_sel_i,
  output logic clk_o
);

  tsmc65_clk_mux2 clk_mux2_inst (.*);

endmodule

module tc_clk_inverter (
  input  logic clk_i,
  output logic clk_o
);

  tsmc65_clk_inverter clk_inv_inst (.*);

endmodule
