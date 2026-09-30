// The capstone, plus the most ordinary thing a design does with a captured
// value: register it, and register a function of it.
//
// This is the shape that made the classifier answer "protected" on a genuinely
// unprotected crossing. `scratch <= captured` is structurally identical to the
// second flop of a two-flop synchronizer, and `combo <= captured ^ 8'hff` is
// structurally identical to combinational logic sitting inside one. Neither is
// a synchronizer: `captured` is a value in use, not a private staging flop —
// it also leaves the module as a port.
//
// The whole design is otherwise the capstone, so the `data` bus still crosses
// clk_a -> clk_b with nothing in between and `req` still crosses through
// sync2. Both verdicts must be unchanged by the presence of downstream logic.
module downstream_use (
    input            clk_a,
    input            clk_b,
    input            rst_n,
    output    [7:0]  captured,
    output reg [7:0] scratch,
    output reg [7:0] combo
);
  wire req; wire [7:0] data; wire req_sync;

  producer u_prod (.clk_a(clk_a), .rst_n(rst_n), .req(req), .data(data));
  sync2    u_sync (.clk(clk_b), .rst_n(rst_n), .d(req), .q(req_sync));
  consumer u_cons (.clk_b(clk_b), .rst_n(rst_n), .req_sync(req_sync),
                   .data_bus(data), .captured(captured));

  always @(posedge clk_b or negedge rst_n)
    if (!rst_n) begin
      scratch <= 8'b0;
      combo   <= 8'b0;
    end else begin
      scratch <= captured;             // direct: read as a two-flop chain
      combo   <= captured ^ 8'hff;     // through logic: read as combo-in-sync
    end
endmodule
