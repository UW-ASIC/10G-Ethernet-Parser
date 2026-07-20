`timescale 1ns / 1ps

// my half of header extraction, just tracks which beat were on rn
// field capture goes on top of this next, next pers does the metadata/drop stuff
module ip_parser_header_extraction (
    input   logic        clk,
    input   logic        rst_n,

    // reading off the fifo, header should already start at byte 0 here
    input   logic [63:0] m_axis_tdata,
    input   logic [7:0]  m_axis_tkeep,
    input   logic       m_axis_tvalid,
    output  logic        m_axis_tready,
    input   logic        m_axis_tlast,
    input   logic [0:0]  m_axis_tuser,

    // pulses high the cycle dst_ip lands, tells next guy the fields are ready
    output  logic        capture_done
);

assign m_axis_tready = 1'b1; // dis is a placeholder

// only count a beat if it actually went thru this cycle, tvalid by itself
// wouldve double counted during backpressure stalls
logic beat_valid;
assign beat_valid = m_axis_tvalid && m_axis_tready;

// which header beat we're capturing, 0/1/2, then it sits at 3 ("done") since
// anything after dst_ip is payload not header anymore
logic [1:0] beat_cnt;

// beat 0 fields, top half of the ip header. bit slices from the header
// extraction task doc, dont ask me why theyre numbered backwards its
// network byte order lol
logic [3:0]  version;
logic [3:0]  ihl;
logic [5:0]  dscp;
logic [1:0]  ecn;
logic [15:0] total_len;

// beat 1 fields, ttl/protocol are top of the word, src_ip is the low 32 bits
logic [7:0]  ttl;
logic [7:0]  protocol;
logic [31:0] src_ip;

// beat 2, just dst_ip, top half of the word (bottom half is payload already)
logic [31:0] dst_ip;

// same condition that triggers the dst_ip grab below, just exposed as a pulse
assign capture_done = beat_valid && (beat_cnt == 2'd2);

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        beat_cnt <= 2'd0;
    end else if (beat_valid) begin
        // beat 0 -> grab version/ihl/dscp/ecn/total_len off the top 4 bytes
        if (beat_cnt == 2'd0) begin
            version   <= m_axis_tdata[63:60];
            ihl       <= m_axis_tdata[59:56];
            dscp      <= m_axis_tdata[55:50];
            ecn       <= m_axis_tdata[49:48];
            total_len <= m_axis_tdata[47:32];
        end else if (beat_cnt == 2'd1) begin
            // beat 1 -> ttl, protocol, and the whole src_ip lands here
            ttl      <= m_axis_tdata[63:56];
            protocol <= m_axis_tdata[55:48];
            src_ip   <= m_axis_tdata[31:0];
        end else if (beat_cnt == 2'd2) begin
            // beat 2 -> dst_ip, and only this beat, else payload bytes would
            // keep stomping on it every cycle after
            dst_ip <= m_axis_tdata[63:32];
        end

        if (m_axis_tlast)
            beat_cnt <= 2'd0;
        else if (beat_cnt != 2'd3)
            beat_cnt <= beat_cnt + 2'd1;
    end
end

endmodule
