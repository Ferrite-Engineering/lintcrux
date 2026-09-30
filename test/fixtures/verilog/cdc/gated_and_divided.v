// Clock-tree shapes that open core structurally cannot resolve.
//
// Everything here is driven by ONE oscillator, so there is no asynchronous
// crossing anywhere in this file and a correct tool reports nothing.
//
// Open core reports several, and it is not a bug: it resolves a clock to the
// literal net driving CLK, so `gclk` (gated) and `div2` (divided) look like
// clocks unrelated to `clk`, and every transfer between those register groups
// looks like a crossing. With no clock model it cannot safely merge them, and
// under-reporting a CDC hazard is worse than over-reporting one.
//
// The Pro resolver traces the tree: through the enable gate to `clk`, and
// through the divider flop to the clock that drives *it*. Same netlist, no
// user input, no findings.
module gated_and_divided (
    input  wire clk,
    input  wire rst_n,
    input  wire enable,
    input  wire [7:0] data_in,
    output reg  [7:0] data_out
);

  // A clock-gating cell: `gclk` is synchronous to `clk`.
  wire gclk = clk & enable;

  // A clock divider: `div2` toggles on `clk`, so it is synchronous to `clk`.
  reg div2;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) div2 <= 1'b0;
    else div2 <= ~div2;
  end

  // Three register groups, three different CLK nets, ONE clock domain.
  reg [7:0] stage_a;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) stage_a <= 8'd0;
    else stage_a <= data_in;
  end

  reg [7:0] stage_b;
  always @(posedge gclk or negedge rst_n) begin
    if (!rst_n) stage_b <= 8'd0;
    else stage_b <= stage_a;
  end

  always @(posedge div2 or negedge rst_n) begin
    if (!rst_n) data_out <= 8'd0;
    else data_out <= stage_b;
  end

endmodule
