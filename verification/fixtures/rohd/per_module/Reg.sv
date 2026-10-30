module Reg (
input logic clk,
input logic [7:0] d,
output logic [7:0] q
);
// Source files:
//   0: lib/design.dart
always_ff @(posedge clk) q <= d;  // flipflop // ROHD: 0:37:10 0:63:17
endmodule : Reg