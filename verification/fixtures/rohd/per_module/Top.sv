module Top (
input logic clk,
input logic [8:0] pkt,
input logic [7:0] k,
output logic [7:0] out
);
// Source files:
//   0: lib/design.dart
logic [7:0] data_slice;
logic [7:0] gated;             // ROHD: 0:59:19
logic [7:0] inner_pkt_data;    // ROHD: 0:8:9 0:51:19
logic inner_pkt_valid;         // ROHD: 0:9:9 | 0:51:19
logic [7:0] sum;               // ROHD: 0:24:15 0:58:19
logic valid_bit;
assign valid_bit = inner_pkt_valid; // ROHD: 0:55:19
assign data_slice = inner_pkt_data; // ROHD: 0:53:18
Reg  reg_(.clk(clk),.d(gated),.q(out)); // ROHD: 0:33:29 0:63:17
//  combinational              // ROHD: 0:60:5
always_comb begin
  if(valid_bit) begin
      gated = sum;
  end   else begin
      gated = 8'h0;
  end 

end

Adder  adder(.a(data_slice),.b(k),.sum(sum)); // ROHD: 0:21:29 0:58:19
assign inner_pkt_data = pkt[7:0];  // bussubset // ROHD: 0:52:11
assign inner_pkt_valid = pkt[8];  // bussubset_0 // ROHD: ^
endmodule : Top