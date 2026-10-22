// Copyright 2026 Ferrite Engineering LLC
// SPDX-License-Identifier: Apache-2.0
//
// Types and a helper shared by both clock domains of pkg_cdc_top.

package cdc_types_pkg;

  typedef logic [7:0] byte_t;

  typedef enum logic [1:0] {
    Idle  = 2'b00,
    Count = 2'b01,
    Hold  = 2'b10
  } mode_e;

  function automatic byte_t next_byte(byte_t b, mode_e mode);
    return (mode == Count) ? b + 8'd1 : b;
  endfunction

endpackage : cdc_types_pkg
