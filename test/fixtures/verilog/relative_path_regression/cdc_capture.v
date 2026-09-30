// A regression fixture for the Verilator "relative source path + no working
// directory" defect: the project root is passed absolute while the source is
// named relative to it, which is the shape that used to make the engine
// resolve the file against the wrong directory and report nothing.
//
// Kept deliberately small; Verilator flags two lints on `guard_band`:
//
//   * WIDTHTRUNC   — the 8-bit `async_in` is assigned into the 4-bit
//                    `guard_band` register (a truncating assignment).
//   * UNUSEDSIGNAL — `guard_band` is written but never read anywhere.
//
// `sync_stage` is a genuine two-flop synchronizer stage (written AND read)
// so Verilator does NOT flag it — the regression test checks that the
// violations land on `guard_band`, not on the synchronizer.
module cdc_capture (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] async_in,
    output reg  [7:0] sync_out
);
    // Two-flop synchronizer stage — written here, read into sync_out.
    reg [7:0] sync_stage;

    // 4-bit guard band, fed by the full-width input (WIDTHTRUNC) and never
    // read (UNUSEDSIGNAL).
    reg [3:0] guard_band;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_stage <= 8'b0;
            sync_out   <= 8'b0;
            guard_band <= 4'b0;
        end else begin
            sync_stage <= async_in;
            sync_out   <= sync_stage;
            guard_band <= async_in; // 8-bit -> 4-bit truncation
        end
    end
endmodule
