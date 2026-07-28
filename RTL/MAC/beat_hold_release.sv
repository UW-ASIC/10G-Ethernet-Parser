`default_nettype none

module beat_hold_release #(
    parameter int DATA_W = 64,
    parameter int KEEP_W = 8,
    parameter int DELAY_W = 2,
)

(
    input logic         clk,
    input logic         rst_n,
    input logic         tready,
    input logic         capture,
    input logic [DELAY_W-1:0] capture_delay,
    input logic [DATA_W-1:0]  capture_data,
    input logic [KEEP_W-1:0]  capture_keep,

    output logic        release_valid,
    output logic [DATA_W-1:0] release_data,
    output logic [KEEP_W-1:0] release_keep
);

logic       pending_q;
logic [DELAY_W-1:0] delay_q;
logic [DATA_W-1:0]  data_q;
logic [KEEP_W-1:0]  keep_q;

assign release_valid = pending_q && (delay_q == '0);
assign release_data = data_q;
assign release_keep = keep_q;


always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        pending_q <= 1'b0;
        delay_q <= '0;
    end

    else if (tready) begin
        if (capture) begin
            pending_q <= 1'b1;
            delay_q <= capture_delay;
            data_q <= capture_data;
            keep_q <= capture_keep;
        end

        else if (release_valid) begin
            pending_q <= 1'b0;
        end

        else if (pending_q) begin
            delay_q <= delay_q - 1'b1;
        end
    end
end
endmodule