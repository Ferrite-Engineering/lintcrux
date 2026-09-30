// A deliberately imperfect ALU. Every defect below is real and is the
// kind a linter is bought to find — none of it is a syntax error, so a
// compiler would accept the file and a testbench might well pass.
//
// Do not "fix" these. The README explains what each one teaches.
//
// A note on comment style: a comment whose first word is the linter's own
// name is parsed by Verilator as a metacomment pragma and aborts the whole
// file. Engine names therefore never lead a comment here.
module alu #(
    parameter WIDTH = 8
) (
    input  logic             clk,
    input  logic             rst_n,
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
    input  logic [2:0]       op,
    output logic [WIDTH-1:0] result,
    output logic [3:0]       nibble,
    output logic             zero
);

  // Declared, driven, never read. UNUSEDSIGNAL.
  logic [WIDTH-1:0] carry_scratch;

  // Read below, never driven anywhere. UNDRIVEN.
  logic             overflow_flag;

  logic [WIDTH-1:0] next_result;

  // An incomplete case with no default: `op` has 8 encodings and only 5
  // are covered, so the other 3 hold `next_result` — an inferred latch in
  // what reads like combinational logic. CASEINCOMPLETE, and the bug it
  // stands for is one of the most common in RTL.
  always_comb begin
    case (op)
      3'b000: next_result = a + b;
      3'b001: next_result = a - b;
      3'b010: next_result = a & b;
      3'b011: next_result = a | b;
      3'b100: next_result = a ^ b;
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      result        <= '0;
      carry_scratch <= '0;
    end else begin
      result        <= next_result;
      carry_scratch <= a + b;
    end
  end

  // 8 bits assigned to 4. Silently drops the top half. This one is
  // default-on in Verilator, unlike the four above, which only appear
  // because LintCrux passes -Wall.
  assign nibble = a;

  assign zero   = (result == '0) | overflow_flag;

endmodule
