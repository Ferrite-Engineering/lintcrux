// Pin-constraint fixture top. Written for this fixture.
module top (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       btn,
    output wire [3:0] led
);
    reg [3:0] count;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) count <= 4'd0;
        else if (btn) count <= count + 4'd1;
    assign led = count;
endmodule
