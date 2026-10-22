// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0
//
// Two clock domains whose types come from a package.
//
// clk_a counts a byte and toggles req_a. clk_b samples the byte directly
// (an unsynchronized 8-bit crossing) and takes req_a through a two-flop
// synchronizer (a safe single-bit crossing).

module pkg_cdc_top
  import cdc_types_pkg::*;
(
  input  logic  clk_a,
  input  logic  clk_b,
  input  mode_e mode_a,
  output byte_t data_b,
  output logic  req_b
);

  byte_t data_a;
  logic  req_a;

  always_ff @(posedge clk_a) begin
    data_a <= next_byte(data_a, mode_a);
    req_a  <= ~req_a;
  end

  always_ff @(posedge clk_b) data_b <= data_a;

  logic req_meta;
  always_ff @(posedge clk_b) begin
    req_meta <= req_a;
    req_b    <= req_meta;
  end

endmodule : pkg_cdc_top
