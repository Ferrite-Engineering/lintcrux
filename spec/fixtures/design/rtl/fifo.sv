// One storage register of the LintCrux MCP goldens' design (spec/mcp/).
module fifo (
  input logic clk
);
  logic [7:0] mem;
  logic       spare;
  always_ff @(posedge clk) mem <= mem + 8'd1;
endmodule
