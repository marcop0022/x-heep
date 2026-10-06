// Copyright 2022 EPFL and Politecnico di Torino.
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// TSMC 65nm inout pad (PDUW0204CDG), same interface as the
// other technologies' pad_cell_inout. Based on polheepo's
// hw/asic/rtl/tsmc65_pad_cell_inout.sv.
// inout: driver enabled by pad_oe_i (OEN active low); pull-up/down enabled by
// pad_attributes_i[0] (PE), as in polheepo.

module pad_cell_inout #(
    parameter PADATTR = 0
) (
    input logic pad_in_i,
    input logic pad_oe_i,
    output logic pad_out_o,
    inout logic pad_io,
    input logic [PADATTR-1:0] pad_attributes_i
);

  (* keep *)
  PDUW0204CDG pad_cell_inout (
      .I  (pad_in_i),
      .OEN(~pad_oe_i),
      .PE (pad_attributes_i[0]),
      .IE (1'b1),
      .DS (1'b1),
      .PAD(pad_io),
      .C  (pad_out_o)
  );

endmodule
