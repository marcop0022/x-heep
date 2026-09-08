// Copyright 2026 Politecnico di Torino.
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Transparent simulation stubs for the IHP-SG13G2 IO pad cells, matching the
// FUNCTIONAL pin set the gate netlist actually connects (the netlist was
// synthesised from the black-box stubs, i.e. without USE_POWER_PINS, so it
// wires only pad/c2p/c2p_en/p2c and leaves vdd/vss/iovdd/iovss off).
//
// The real PDK models (sg13g2_io/verilog/sg13g2_io.v) declare those supplies
// and gate the buffer on them; left unconnected they drive the pad to X and
// poison the whole chip. These stubs are used INSTEAD of that file for the
// post-synthesis simulation.

`timescale 1ns / 1ps

module sg13g2_IOPadIn (
    input  wire pad,
    output wire p2c
);
  assign p2c = pad;
endmodule

module sg13g2_IOPadOut4mA (
    output wire pad,
    input  wire c2p
);
  assign pad = c2p;
endmodule

module sg13g2_IOPadInOut4mA (
    inout  wire pad,
    input  wire c2p,     // core -> pad data
    input  wire c2p_en,  // core -> pad output enable (active high)
    output wire p2c      // pad  -> core data
);
  assign pad = c2p_en ? c2p : 1'bz;
  assign p2c = pad;
endmodule

// Power pads: no behaviour needed for functional simulation.
module sg13g2_IOPadVdd ();   endmodule
module sg13g2_IOPadVss ();   endmodule
module sg13g2_IOPadIOVdd (); endmodule
module sg13g2_IOPadIOVss (); endmodule
