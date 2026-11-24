// The top of the LintCrux MCP goldens' design (spec/mcp/).
module top (
  input  logic       clk,
  output logic [7:0] q
);
  assign q = 32'h1;
  logic dbg;
  // verilator lint_off UNUSEDSIGNAL
  logic dbg_unused;
  // verilator lint_on UNUSEDSIGNAL
  fifo u_fifo (.clk(clk));
endmodule
