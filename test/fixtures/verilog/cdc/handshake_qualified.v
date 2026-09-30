// A correctly handshake-qualified bus — the idiom whose absence hurts most.
//
// `data` crosses clk_a -> clk_b completely unsynchronized, and that is
// CORRECT. The receiver never samples it on a whim: it waits for `req`, which
// IS synchronized through a two-flop chain, and by the time `req` arrives the
// bus has been stable for at least a full source-domain cycle.
//
// This is what a careful engineer writes. A structural analyser that does not
// know the pairing sees an unsynchronized 8-bit bus and reports the best code
// in the design as its worst finding — which is precisely how a CDC tool
// teaches people to ignore it.
//
// The pairing is a PROTOCOL fact, not a structural one. Nothing in the netlist
// says `req` qualifies `data`; the same graph would be produced by a design
// where they are unrelated. That is why it takes a `cdc.yaml` declaration and
// cannot be inferred:
//
//     handshakes:
//       - request: req
//         acknowledge: ack
//         data: [data]
//
// The Pro classifier does not take the declaration on trust. It checks that
// `req` is itself synchronized before honouring it — otherwise one line of
// YAML could silence a genuine hazard.
module handshake_qualified (
    input  wire       clk_a,
    input  wire       clk_b,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    input  wire       start,
    output reg  [7:0] data_out,
    output reg        ack
);

  // ── Source domain (clk_a) ────────────────────────────────────────────────
  reg [7:0] data;
  reg       req;
  always @(posedge clk_a or negedge rst_n) begin
    if (!rst_n) begin
      data <= 8'd0;
      req  <= 1'b0;
    end else if (start) begin
      data <= data_in;   // driven, then held stable while req is asserted
      req  <= 1'b1;
    end
  end

  // ── Destination domain (clk_b) ───────────────────────────────────────────
  // The qualifier gets a real two-flop synchronizer. The bus does not need one.
  reg req_meta;
  reg req_sync;
  always @(posedge clk_b or negedge rst_n) begin
    if (!rst_n) begin
      req_meta <= 1'b0;
      req_sync <= 1'b0;
    end else begin
      req_meta <= req;
      req_sync <= req_meta;
    end
  end

  always @(posedge clk_b or negedge rst_n) begin
    if (!rst_n) begin
      data_out <= 8'd0;
      ack      <= 1'b0;
    end else if (req_sync) begin
      data_out <= data;  // safe: sampled only after the synchronized qualifier
      ack      <= 1'b1;
    end
  end

endmodule
