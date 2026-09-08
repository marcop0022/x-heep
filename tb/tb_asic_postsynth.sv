// Copyright 2026 Politecnico di Torino.
// Solderpad Hardware License, Version 2.1, see LICENSE.md for details.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Slim testbench for the post-synthesis (gate-level) simulation of the
// IHP-SG13G2 netlist. The DUT is `asic_x_heep_system_wrapper`, which exposes
// only the 59 pad wires. Firmware is backdoor-loaded into the SRAM arrays
// (memory_subsystem is kept as hierarchy in the netlist) and the boot ROM is
// released via POSTSYNTH_AUTOBOOT (soc_ctrl drives BOOT_EXIT_LOOP=1), so it
// jumps to BOOT_ADDRESS (0x180) without needing JTAG or the SPI flash path.
//
// Plusargs:
//   +firmware=<path>   flash image (.hex), $readmemh-ed into the spiflash model
//   +boot_sel=<0|1>    0 = debug-entry / backdoor (default), 1 = flash boot
//   +max_cycles=<n>    abort after n clock cycles
//   +vcd               dump waveform.vcd
//
// EXIT is observed on the (preserved) soc_ctrl hierarchy inside the netlist.

// shorthands into the preserved netlist "spine"
`define SOC_CTRL  dut.x_heep_system_i.core_v_mini_mcu_i.ao_peripheral_subsystem_i.soc_ctrl_i
`define MEMSS     dut.x_heep_system_i.core_v_mini_mcu_i.memory_subsystem_i
`define CPU       dut.x_heep_system_i.core_v_mini_mcu_i.cpu_subsystem_i

module tb_asic_postsynth;

  // ---------------------------------------------------------------------------
  // clock / reset
  // ---------------------------------------------------------------------------
  localparam time ClkPeriod = 10ns;
  localparam int  ResetWaitCycles = 50;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic boot_sel = 1'b0;

  always #(ClkPeriod / 2) clk = ~clk;

  initial begin : reset_gen
    rst_n = 1'b0;
    repeat (ResetWaitCycles) @(negedge clk);
    rst_n = 1'b1;
  end

  initial $timeformat(-9, 0, " ns", 12);

  // ---------------------------------------------------------------------------
  // pad wires (names match asic_x_heep_system_wrapper)
  // ---------------------------------------------------------------------------
  wire clk_i          = clk;
  wire rst_ni         = rst_n;
  wire boot_select_i  = boot_sel;

  // jtag: held idle (debug not used in this flow)
  wire jtag_tck_i     = 1'b0;
  wire jtag_tms_i     = 1'b0;
  wire jtag_trst_ni   = rst_n;
  wire jtag_tdi_i     = 1'b0;
  wire jtag_tdo_o;

  // uart
  wire uart_rx_i      = 1'b1;   // idle high
  wire uart_tx_o;

  wire exit_valid_o;

  wire ddr_rcv_clk_i  = 1'b0;
  wire ddr_snd_clk_o;

  // gpio (left floating; add pulls if a test needs them)
  wire gpio_0_io, gpio_1_io, gpio_2_io, gpio_3_io, gpio_4_io, gpio_5_io, gpio_6_io;
  wire gpio_7_io, gpio_8_io, gpio_9_io, gpio_10_io, gpio_11_io, gpio_12_io, gpio_13_io;

  // spi flash (boot device)
  wire       spi_flash_sck_io;
  wire       spi_flash_cs_0_io;
  wire       spi_flash_cs_1_io;
  wire [3:0] spi_flash_sd_io;

  // other unused peripheral pads
  wire spi_sck_io, spi_cs_0_io, spi_cs_1_io, spi_sd_0_io, spi_sd_1_io, spi_sd_2_io, spi_sd_3_io;
  wire spi_slave_sck_io, spi_slave_cs_io, spi_slave_miso_io, spi_slave_mosi_io;
  wire pdm2pcm_pdm_io, pdm2pcm_clk_io;
  wire i2s_sck_io, i2s_ws_io, i2s_sd_io;
  wire spi2_cs_0_io, spi2_cs_1_io, spi2_sck_io, spi2_sd_0_io, spi2_sd_1_io, spi2_sd_2_io, spi2_sd_3_io;
  wire i2c_scl_io, i2c_sda_io;

  pullup (i2c_scl_io);
  pullup (i2c_sda_io);

  // ---------------------------------------------------------------------------
  // DUT: the gate-level netlist wrapper
  // ---------------------------------------------------------------------------
  asic_x_heep_system_wrapper dut (
      .clk_i,
      .rst_ni,
      .boot_select_i,
      .jtag_tck_i,
      .jtag_tms_i,
      .jtag_trst_ni,
      .jtag_tdi_i,
      .jtag_tdo_o,
      .uart_rx_i,
      .uart_tx_o,
      .exit_valid_o,
      .ddr_rcv_clk_i,
      .ddr_snd_clk_o,
      .gpio_0_io,
      .gpio_1_io,
      .gpio_2_io,
      .gpio_3_io,
      .gpio_4_io,
      .gpio_5_io,
      .gpio_6_io,
      .gpio_7_io,
      .gpio_8_io,
      .gpio_9_io,
      .gpio_10_io,
      .gpio_11_io,
      .gpio_12_io,
      .gpio_13_io,
      .spi_flash_sck_io (spi_flash_sck_io),
      .spi_flash_cs_0_io(spi_flash_cs_0_io),
      .spi_flash_cs_1_io(spi_flash_cs_1_io),
      .spi_flash_sd_0_io(spi_flash_sd_io[0]),
      .spi_flash_sd_1_io(spi_flash_sd_io[1]),
      .spi_flash_sd_2_io(spi_flash_sd_io[2]),
      .spi_flash_sd_3_io(spi_flash_sd_io[3]),
      .spi_sck_io,
      .spi_cs_0_io,
      .spi_cs_1_io,
      .spi_sd_0_io,
      .spi_sd_1_io,
      .spi_sd_2_io,
      .spi_sd_3_io,
      .spi_slave_sck_io,
      .spi_slave_cs_io,
      .spi_slave_miso_io,
      .spi_slave_mosi_io,
      .pdm2pcm_pdm_io,
      .pdm2pcm_clk_io,
      .i2s_sck_io,
      .i2s_ws_io,
      .i2s_sd_io,
      .spi2_cs_0_io,
      .spi2_cs_1_io,
      .spi2_sck_io,
      .spi2_sd_0_io,
      .spi2_sd_1_io,
      .spi2_sd_2_io,
      .spi2_sd_3_io,
      .i2c_scl_io,
      .i2c_sda_io
  );

  // ---------------------------------------------------------------------------
  // SPI flash boot device
  // ---------------------------------------------------------------------------
  spiflash flash_i (
      .csb(spi_flash_cs_0_io),
      .clk(spi_flash_sck_io),
      .io0(spi_flash_sd_io[0]),  // MOSI
      .io1(spi_flash_sd_io[1]),  // MISO
      .io2(spi_flash_sd_io[2]),
      .io3(spi_flash_sd_io[3])
  );

  // ---------------------------------------------------------------------------
  // UART monitor (inline 8N1 receiver -> console). Baud matches the RTL flow's
  // uartdpi (CLK_FREQUENCY / 20 with CLK_FREQUENCY = 100 MHz). If the console
  // output is garbled, retune this to the value the firmware programs.
  // ---------------------------------------------------------------------------
  localparam int  UartBaud = 100_000_000 / 20;
  localparam time UartBitT = 1s / UartBaud;

  initial begin : uart_mon
    byte ch;
    forever begin
      @(negedge uart_tx_o);            // start bit
      #(UartBitT / 2);
      if (uart_tx_o !== 1'b0) continue; // false start
      for (int b = 0; b < 8; b++) begin
        #(UartBitT);
        ch[b] = uart_tx_o;
      end
      #(UartBitT);                      // stop bit
      $write("%c", ch);
    end
  end

  // ---------------------------------------------------------------------------
  // firmware load + run control
  // ---------------------------------------------------------------------------
  string firmware;
  int    max_cycles = 3_000_000;   // ~30 ms sim time: generous for flash boot + hello_world
  int    hb_ns      = 100_000;     // heartbeat period (sim ns)
  longint cycle_cnt = 0;

  // RAM geometry (configs/general.hjson: 4 contiguous banks of 32 KiB at 0x0)
  localparam int RamBankBytes = 32 * 1024;
  localparam int RamBanks     = 4;

  // Preload the firmware straight into the SRAM behavioural arrays. The netlist
  // keeps memory_subsystem / sram_wrapper as hierarchy (the "spine"), and
  // POSTSYNTH_AUTOBOOT drives soc_ctrl.BOOT_EXIT_LOOP=1 so the boot ROM jumps to
  // BOOT_ADDRESS (0x180, the .init section) right after reset.
  task automatic backdoor_load(input string hexfile);
    logic [7:0]  b [0:RamBanks*RamBankBytes-1];
    logic [31:0] w;
    int bank, waddr;
    foreach (b[i]) b[i] = 8'h00;
    $readmemh(hexfile, b);
    for (int a = 0; a < RamBanks*RamBankBytes; a += 4) begin
      w     = {b[a+3], b[a+2], b[a+1], b[a]};
      bank  = a / RamBankBytes;
      waddr = (a % RamBankBytes) / 4;
      case (bank)
        0: `MEMSS.ram0_i.\genblk2.sram_inst .i_SRAM_1P_behavioral.memory[waddr] = w;
        1: `MEMSS.ram1_i.\genblk2.sram_inst .i_SRAM_1P_behavioral.memory[waddr] = w;
        2: `MEMSS.ram2_i.\genblk2.sram_inst .i_SRAM_1P_behavioral.memory[waddr] = w;
        3: `MEMSS.ram3_i.\genblk2.sram_inst .i_SRAM_1P_behavioral.memory[waddr] = w;
      endcase
    end
    $display("[TB] %t: backdoor-loaded %0s into RAM", $time, hexfile);
  endtask

  initial begin : stimulus
    string boot_arg;

    boot_sel = 1'b0;   // debug-entry path: boot ROM -> jalr BOOT_ADDRESS (0x180)
    if ($value$plusargs("boot_sel=%s", boot_arg))
      boot_sel = (boot_arg == "1") ? 1'b1 : 1'b0;

    void'($value$plusargs("max_cycles=%d", max_cycles));
    void'($value$plusargs("heartbeat_ns=%d", hb_ns));

    if ($test$plusargs("vcd")) begin
      $dumpfile("waveform.vcd");
      $dumpvars(0, tb_asic_postsynth);
    end

    if (!$value$plusargs("firmware=%s", firmware)) begin
      $display("[TB] ERROR: no +firmware=<hex> given");
      $fatal(1);
    end

    // also drop it in the flash model, in case boot_sel=1 is forced
    $readmemh(firmware, flash_i.memory);

    // backdoor into RAM shortly after reset, before the boot ROM jumps
    @(posedge rst_n);
    repeat (10) @(posedge clk);
    backdoor_load(firmware);

    $display("[TB] boot_sel=%0d, max_cycles=%0d", boot_sel, max_cycles);
  end

  // cycle limit
  always @(posedge clk) begin
    if (!rst_n) begin
      cycle_cnt <= 0;
    end else begin
      cycle_cnt <= cycle_cnt + 1;
      if (max_cycles != 0 && cycle_cnt >= max_cycles) begin
        $display("[TB] %t: TIMEOUT at %0d cycles (no EXIT)", $time, cycle_cnt);
        $finish;
      end
    end
  end

  // ---------------------------------------------------------------------------
  // progress instrumentation
  // ---------------------------------------------------------------------------
  // heartbeat: also report whether the spine is out of X and if the CPU is
  // touching the soc_ctrl register bus / the RAM
  int soc_reg_evts   = 0;
  int ram0_rd_evts   = 0;
  int ram0_wr_evts   = 0;
  int cpu_clk_edges  = 0;
  int cpu_ifetch_evts = 0;
  always @(`SOC_CTRL.reg_req_i)                                     soc_reg_evts++;
  always @(posedge `MEMSS.ram0_i.req_i) if (!`MEMSS.ram0_i.we_i)    ram0_rd_evts++;
  always @(posedge `MEMSS.ram0_i.req_i) if ( `MEMSS.ram0_i.we_i)    ram0_wr_evts++;
  always @(posedge `CPU.clk_i)                                      cpu_clk_edges++;
  always @(`CPU.core_instr_req_o)                                   cpu_ifetch_evts++;

  initial forever begin
    #(hb_ns * 1ns);
    $display("[TB] hb t=%t cyc=%0d | CPU: clk_edges=%0d rst_ni=%b sleep=%b ifetch_evts=%0d | soc_reg_evts=%0d ram0_rd=%0d ram0_wr=%0d | uart_tx=%b",
             $time, cycle_cnt,
             cpu_clk_edges, `CPU.rst_ni, `CPU.core_sleep_o, cpu_ifetch_evts,
             soc_reg_evts, ram0_rd_evts, ram0_wr_evts, uart_tx_o);
  end

  // one-shot markers
  initial begin
    @(posedge rst_n);
    repeat (5) @(posedge clk);
    $display("[TB] %t: post-reset  soc_ctrl.rst_ni=%b boot_select_i=%b  reg_req_i=%b",
             $time, `SOC_CTRL.rst_ni, `SOC_CTRL.boot_select_i, `SOC_CTRL.reg_req_i);
  end
  initial begin
    @(negedge spi_flash_cs_0_io);
    $display("[TB] %t: SPI-flash CS asserted -- boot ROM is reading the flash", $time);
  end

  // ---------------------------------------------------------------------------
  // EXIT detection -- peek the preserved soc_ctrl hierarchy in the netlist
  // ---------------------------------------------------------------------------
  wire        soc_exit_valid =
      dut.x_heep_system_i.core_v_mini_mcu_i.ao_peripheral_subsystem_i.soc_ctrl_i.exit_valid_o;
  wire [31:0] soc_exit_value =
      dut.x_heep_system_i.core_v_mini_mcu_i.ao_peripheral_subsystem_i.soc_ctrl_i.exit_value_o;

  always @(posedge clk) begin
    if (rst_n && soc_exit_valid) begin
      if (soc_exit_value == 0) $display("[TB] %t: EXIT SUCCESS", $time);
      else                     $display("[TB] %t: EXIT FAILURE (%0d)", $time, soc_exit_value);
      $finish;
    end
  end

endmodule
