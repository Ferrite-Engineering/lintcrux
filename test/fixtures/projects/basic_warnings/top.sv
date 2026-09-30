// Hand-crafted fixture: one UNUSEDSIGNAL and one UNDRIVEN, captured from a
// real run. Three traps this fixture exists to keep us out of:
//
//   1. A comment must not START with the engine's own name. Its parser
//      reads such a comment as a metacomment pragma, fails the file with
//      %Error-BADVLTPRAGMA, and lints nothing at all. The prefix match is
//      loose — even a word like `VerilatorEngine` at the head of a comment
//      trips it. The previous version of this header did exactly that, so
//      the fixture reported zero violations for its whole life.
//   2. Do NOT name a signal `*unused*`. The default
//      `--unused-regexp '*unused*'` suppresses UNUSEDSIGNAL for it, so the
//      one name that reads as "this should warn" is the one name that
//      cannot.
//   3. UNUSEDSIGNAL / UNDRIVEN are off unless `-Wall` is passed; the
//      engine's `defaultWarnFlags` supplies it.
//
// `unread_sig` is driven and never read   -> UNUSEDSIGNAL
// `undriven_sig` is read and never driven -> UNDRIVEN
//
// The module name matches the file name, so DECLFILENAME (also a -Wall
// check) stays quiet. expected.sarif.json is captured from a real run; see
// capture.json in this directory for the binary and version.
module top (
  input  logic clk,
  output logic out
);
  logic unread_sig;
  logic undriven_sig;
  assign unread_sig = clk;
  assign out = clk | undriven_sig;
endmodule
