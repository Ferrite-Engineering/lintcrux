module Adder (
input logic [7:0] a,
input logic [7:0] b,
output logic [7:0] sum
);
// Source files:
//   0: lib/design.dart
logic _a_add_b_carry;          // ROHD: 0:26:18 0:58:19
logic [7:0] partial;           // ROHD: 0:25:21 | 0:58:19
assign sum = partial;          // ROHD: 0:24:15 | 0:58:19
assign {_a_add_b_carry, partial} = a + b; // ROHD: 0:26:18 | 0:58:19
endmodule : Adder