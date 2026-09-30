// The classic wrong fix: an 8-bit bus "synchronized" one bit at a time.
//
// This is the fixture that shows why the Pro classifier is worth more than a
// false-positive filter. Every bit of `data` goes through its own correct
// two-flop chain, so:
//
//   * every bit is individually protected against metastability,
//   * a per-bit analysis finds nothing wrong,
//   * and the bus is still broken.
//
// The eight chains resolve independently. Bits that changed together in the
// `clk_a` domain can land in different `clk_b` cycles, so the receiver can
// latch a value that never existed in the source domain — the same incoherence
// as an unsynchronized bus, except now it is invisible.
//
// It is more dangerous than doing nothing, because it looks careful in review
// and it silences every warning a simpler tool would raise. A CDC tool that
// merely stopped complaining here would be actively harmful, which is why
// `cdc/per-bit-sync-bus` is an error rather than a pass.
//
// The correct fix is a handshake or an async FIFO — see handshake_qualified.v.
module per_bit_sync_bus (
    input  wire       clk_a,
    input  wire       clk_b,
    input  wire       rst_n,
    input  wire [7:0] data_in,
    output reg  [7:0] data_out
);

  // Source domain.
  reg [7:0] data_a;
  always @(posedge clk_a or negedge rst_n) begin
    if (!rst_n) data_a <= 8'd0;
    else data_a <= data_in;
  end

  // Destination domain: eight independent two-flop synchronizers.
  reg [7:0] sync_meta;
  reg [7:0] sync_stable;
  always @(posedge clk_b or negedge rst_n) begin
    if (!rst_n) begin
      sync_meta   <= 8'd0;
      sync_stable <= 8'd0;
    end else begin
      sync_meta   <= data_a;
      sync_stable <= sync_meta;
    end
  end

  always @(posedge clk_b or negedge rst_n) begin
    if (!rst_n) data_out <= 8'd0;
    else data_out <= sync_stable;
  end

endmodule
