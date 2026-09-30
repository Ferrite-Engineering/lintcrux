// Hand-crafted fixture: exercise Verilator + Verible + Slang simultaneously.
// Each engine flags a different issue.
//
// A comment whose first word is "Verilator" is parsed by Verilator as a
// metacomment pragma and aborts the whole run with %Error-BADVLTPRAGMA —
// which is what the two trailing comments below used to do. Engine names
// therefore never lead a comment in this corpus. Signals also avoid the
// name `*unused*`, which Verilator's default --unused-regexp suppresses.
//
// Until 2026-08-03 the "and Slang" half of the first line was aspirational:
// nothing in this file was a Slang finding, so a Slang run over it returned
// an empty diagnostic array. That is exactly the signature of a *broken*
// Slang invocation — which is how the `--json-diagnostics` defect went
// unnoticed — so the fixture could not tell a working adapter from a dead
// one. The empty `if` body below is a Slang `-Wempty-body` diagnostic, on
// by default, and is flagged by neither Verilator nor Verible.
module multi_engine (
  input  logic clk,
  output logic out
);
	logic	tabbed;	// tabs on this line -> verible no-tabs
  logic unread_sig;     // driven, never read -> verilator UNUSEDSIGNAL
  assign unread_sig = clk;
  assign out = clk;
  always_comb begin
    if (clk) ;          // empty if body -> slang empty-body
  end
endmodule
