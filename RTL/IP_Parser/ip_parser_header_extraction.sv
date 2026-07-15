`timescale 1ns / 1ps

module ip_parser_header_extraction (
    input   logic        clk,
    input   logic        rst_n,

    input   logic [63:0] m_axis_tdata,
    input   logic [7:0]  m_axis_tkeep,
    input   logic       m_axis_tvalid,
    output  logic        m_axis_tready,
    input   logic        m_axis_tlast,
    input   logic [0:0]  m_axis_tuser
);

assign m_axis_tready = 1'b1; // dis is a placeholder

logic beat_valid;
assign beat_valid = m_axis_tvalid && m_axis_tready;

logic [1:0] beat_cnt;

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        beat_cnt <= 2'd0;
    end else if (beat_valid) begin
        if (m_axis_tlast)
            beat_cnt <= 2'd0;
        else if (beat_cnt != 2'd2)
            beat_cnt <= beat_cnt + 2'd1;
    end
end

endmodule
