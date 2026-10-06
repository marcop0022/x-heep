// Copyright 2022 EPFL and Politecnico di Torino.
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// SRAM wrapper for the TSMC 65nm LP single-port SRAM macros (memory compiler
// tsn65lpllspsramwor, 220a), same interface as the other technologies'
// sram_wrapper. Based on polheepo's hw/asic/rtl/sram_wrapper.sv.
// The macros must be generated with the memory compiler (see polheepo's
// hw/asic/memories) and found by scripts/asic/tech/tsmc65.tcl:
//   1024 words: TS1N65LPLL1024X32M8     2048 words: TS1N65LPLL2048X32M8
//   4096 words: TS1N65LPLL4096X32M8     8192 words: TS1N65LPLL8192X32M16
// All have a bit-write mask (BWEB), so sub-word stores are supported natively.

module sram_wrapper #(
    parameter int unsigned NumWords = 32'd1024,  // Number of Words in data array
    parameter int unsigned DataWidth = 32'd32,  // Data signal width
    // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
    parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1
) (
    input  logic                   clk_i,
    input  logic                   rst_ni,
    // input ports
    input  logic                   req_i,
    input  logic                   we_i,
    input  logic [  AddrWidth-1:0] addr_i,
    input  logic [           31:0] wdata_i,
    input  logic [            3:0] be_i,
    // power manager signals (power gating/retention not supported)
    input  logic                   pwrgate_ni,
    output logic                   pwrgate_ack_no,
    input  logic                   set_retentive_ni,
    // output ports
    output logic [           31:0] rdata_o
);

  // Not supported
  assign pwrgate_ack_no = pwrgate_ni;

  // Byte enable -> active-low bit-write enable
  logic [31:0] bweb;
  assign bweb = ~{{8{be_i[3]}}, {8{be_i[2]}}, {8{be_i[1]}}, {8{be_i[0]}}};

  // Common connections: BIST disabled (normal mode), asynchronous write-through
  // disabled, timing selection as suggested by the documentation.
`define TSMC65_SRAM_PORTS \
      .BIST (1'b0), \
      .AWT  (1'b0), \
      .CLK  (clk_i), \
      .CEB  (~req_i), \
      .WEB  (~we_i), \
      .A    (addr_i), \
      .D    (wdata_i), \
      .BWEB (bweb), \
      .AM   ('0), \
      .DM   ('0), \
      .BWEBM('1), \
      .CEBM (1'b1), \
      .WEBM (1'b1), \
      .TSEL (2'b01), \
      .Q    (rdata_o)

  generate
    if (DataWidth != 32) begin : gen_error_width
      $error("sram_wrapper (tsmc65): DataWidth %0d not implemented.", DataWidth);
    end

    case (NumWords)
      1024: begin : gen_1024
        (* keep *)
        TS1N65LPLL1024X32M8 sram_inst (`TSMC65_SRAM_PORTS);
      end
      2048: begin : gen_2048
        (* keep *)
        TS1N65LPLL2048X32M8 sram_inst (`TSMC65_SRAM_PORTS);
      end
      4096: begin : gen_4096
        (* keep *)
        TS1N65LPLL4096X32M8 sram_inst (`TSMC65_SRAM_PORTS);
      end
      8192: begin : gen_8192
        (* keep *)
        TS1N65LPLL8192X32M16 sram_inst (`TSMC65_SRAM_PORTS);
      end
      default: begin : gen_error_size
        $error("sram_wrapper (tsmc65): NumWords %0d not implemented.", NumWords);
      end
    endcase
  endgenerate

`undef TSMC65_SRAM_PORTS

endmodule
