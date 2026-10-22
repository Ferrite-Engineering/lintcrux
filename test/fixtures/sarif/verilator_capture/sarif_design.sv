// Fixture for LintCrux's Verilator SARIF ingestion. Each construct below
// raises one Verilator warning when linted with -Wall:
//
//   WIDTHTRUNC   `y = a` drops two bits
//   UNUSEDSIGNAL `unread_sig` is driven and never read
//   UNDRIVEN     `undriven_sig` is read and never driven
//   MULTIDRIVEN  `md` is driven from two clocks (two related locations)
//
// The module name matches the file name so DECLFILENAME stays quiet.
module sarif_design (
  input  logic       clk,
  input  logic       clk2,
  input  logic [3:0] a,
  output logic [1:0] y,
  output logic       md,
  output logic [7:0] wide
);
  logic unread_sig;
  logic undriven_sig;
  assign unread_sig = clk;
  assign y = a;
  assign wide = {undriven_sig, 7'b0};
  always_ff @(posedge clk) md <= 1'b1;
  always_ff @(posedge clk2) md <= 1'b0;
endmodule
