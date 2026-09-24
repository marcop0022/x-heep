// Copyright 2022 OpenHW Group
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1

module sram_wrapper #(
    parameter int unsigned NumWords = 32'd1024,  // Number of Words in data array
    parameter int unsigned DataWidth = 32'd32,  // Data signal width
    // DEPENDENT PARAMETERS, DO NOT OVERWRITE!
    parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1
) (
    input  logic clk_i,
    input  logic rst_ni,
    // input ports
    input  logic req_i,
    input  logic we_i,
    input  logic [AddrWidth-1:0] addr_i,
    input  logic [31:0] wdata_i,
    input  logic [3:0] be_i,
    input  logic pwrgate_ni,
    output logic pwrgate_ack_no,
    input  logic [core_v_mini_mcu_pkg::NUM_BANKS-1:0] set_retentive_ni,
    // output ports
    output logic [31:0] rdata_o
);

// verilator lint_off MODMISSING
    // Not supported
    assign pwrgate_ack_no = pwrgate_ni;

    generate
        if (DataWidth != 32) begin
          $error("Bank size not implemented.");
        end

        case (NumWords)
            256: begin
                (* keep, blackbox *)
                RM_IHPSG13_1P_256x32_c2_bm_bist sram_inst (
                    .A_CLK      (clk_i),
                    .A_MEN      (req_i),
                    .A_WEN      (we_i),
                    .A_REN      (!we_i),
                    .A_ADDR     (addr_i),
                    .A_DIN      (wdata_i),
                    .A_DLY      (1'b1),
                    .A_DOUT     (rdata_o),
                    .A_BM       ({{8{be_i[3]}}, {8{be_i[2]}}, {8{be_i[1]}}, {8{be_i[0]}}}),
                    .A_BIST_CLK (1'b0),
                    .A_BIST_EN  (1'b0),
                    .A_BIST_MEN (1'b0),
                    .A_BIST_WEN (1'b0),
                    .A_BIST_REN (1'b0),
                    .A_BIST_ADDR('0),
                    .A_BIST_DIN ('0),
                    .A_BIST_BM  ('0)
                );
            end
            512: begin
                (* keep, blackbox *)
                RM_IHPSG13_1P_512x32_c2_bm_bist sram_inst (
                    .A_CLK      (clk_i),
                    .A_MEN      (req_i),
                    .A_WEN      (we_i),
                    .A_REN      (!we_i),
                    .A_ADDR     (addr_i),
                    .A_DIN      (wdata_i),
                    .A_DLY      (1'b1),
                    .A_DOUT     (rdata_o),
                    .A_BM       ({{8{be_i[3]}}, {8{be_i[2]}}, {8{be_i[1]}}, {8{be_i[0]}}}),
                    .A_BIST_CLK (1'b0),
                    .A_BIST_EN  (1'b0),
                    .A_BIST_MEN (1'b0),
                    .A_BIST_WEN (1'b0),
                    .A_BIST_REN (1'b0),
                    .A_BIST_ADDR('0),
                    .A_BIST_DIN ('0),
                    .A_BIST_BM  ('0)
                );
            end
            1024: begin
                (* keep, blackbox *)
                RM_IHPSG13_1P_1024x32_c2_bm_bist sram_inst (
                    .A_CLK      (clk_i),
                    .A_MEN      (req_i),
                    .A_WEN      (we_i),
                    .A_REN      (!we_i),
                    .A_ADDR     (addr_i),
                    .A_DIN      (wdata_i),
                    .A_DLY      (1'b1),
                    .A_DOUT     (rdata_o),
                    .A_BM       ({{8{be_i[3]}}, {8{be_i[2]}}, {8{be_i[1]}}, {8{be_i[0]}}}),
                    .A_BIST_CLK (1'b0),
                    .A_BIST_EN  (1'b0),
                    .A_BIST_MEN (1'b0),
                    .A_BIST_WEN (1'b0),
                    .A_BIST_REN (1'b0),
                    .A_BIST_ADDR('0),
                    .A_BIST_DIN ('0),
                    .A_BIST_BM  ('0)
                );
            end
            // The IHP-SG13G2 PDK SRAM set has no 4096x32 single-port cut, and its only
            // 8192x32 cut (RM_IHPSG13_1P_8192x32_c4) has no byte mask (sb/sh would clobber
            // the whole word). Both sizes are therefore built from NumWords/2048
            // RM_IHPSG13_1P_2048x32_c2_bm_bist macros selected by the top address bits.
            // Each access enables only the addressed macro (A_MEN gated by the select),
            // and the read-data mux uses the select delayed by one cycle to match the
            // SRAM read latency. 4096: w25q128jw flash controller LLC cache
            // (N_SETS*SECTOR_SIZE_WORDS = 4*1024); 8192: 32 KiB code/data banks.
            4096, 8192: begin : gen_sram_2048_split
                localparam int unsigned NumMacros = NumWords / 2048;
                localparam int unsigned SelWidth = $clog2(NumMacros);

                logic [SelWidth-1:0]        bank_sel;
                logic [SelWidth-1:0]        bank_sel_q;
                logic [NumMacros-1:0][31:0] rdata_macro;

                assign bank_sel = addr_i[AddrWidth-1:11];

                always_ff @(posedge clk_i or negedge rst_ni) begin
                    if (!rst_ni) bank_sel_q <= '0;
                    else if (req_i) bank_sel_q <= bank_sel;
                end

                assign rdata_o = rdata_macro[bank_sel_q];

                for (genvar i = 0; i < NumMacros; i++) begin : gen_macro
                    (* keep, blackbox *)
                    RM_IHPSG13_1P_2048x32_c2_bm_bist sram_inst (
                        .A_CLK      (clk_i),
                        .A_MEN      (req_i & (bank_sel == SelWidth'(i))),
                        .A_WEN      (we_i),
                        .A_REN      (!we_i),
                        .A_ADDR     (addr_i[10:0]),
                        .A_DIN      (wdata_i),
                        .A_DLY      (1'b1),
                        .A_DOUT     (rdata_macro[i]),
                        .A_BM       ({{8{be_i[3]}}, {8{be_i[2]}}, {8{be_i[1]}}, {8{be_i[0]}}}),
                        .A_BIST_CLK (1'b0),
                        .A_BIST_EN  (1'b0),
                        .A_BIST_MEN (1'b0),
                        .A_BIST_WEN (1'b0),
                        .A_BIST_REN (1'b0),
                        .A_BIST_ADDR('0),
                        .A_BIST_DIN ('0),
                        .A_BIST_BM  ('0)
                    );
                end
            end
            default: $error("Bank size not implemented.");
        endcase
    endgenerate
// verilator lint_on MODMISSING

endmodule
