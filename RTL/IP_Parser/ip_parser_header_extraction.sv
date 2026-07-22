`timescale 1ns / 1ps

// ============================================================================
// ip_parser_header_extraction
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
    output  logic        capture_done,
    // pulses if tlast shows up before we got the full header (runt packet) -
    // whatever we captured is stale/partial, next guy should just drop it
    output  logic        header_incomplete,
    // the actual captured fields, handed off to the metadata/drop block
    output  logic [3:0]  version,
    output  logic [3:0]  ihl,
    output  logic [5:0]  dscp,
    output  logic [1:0]  ecn,
    output  logic [15:0] total_len,
    output  logic [7:0]  ttl,
    output  logic [7:0]  protocol,
    output  logic [31:0] src_ip,
    output  logic [31:0] dst_ip
);
assign m_axis_tready = 1'b1; // dis is a placeholder
// only count a beat if it actually went thru this cycle, tvalid by itself
// wouldve double counted during backpressure stalls
logic beat_valid;
assign beat_valid = m_axis_tvalid && m_axis_tready;
// which header beat we're capturing, 0/1/2, then it sits at 3 ("done") since
// anything after dst_ip is payload not header anymore
logic [1:0] beat_cnt;
// beat 0/1/2 fields are all module outputs now (see port list above)
// same condition that triggers the dst_ip grab below, just exposed as a pulse
assign capture_done = beat_valid && (beat_cnt == 2'd2);
// tlast landed while we were still on beat 0 or 1 -> dst_ip (and maybe more)
// never got captured this packet, registers still hold leftovers from before
assign header_incomplete = beat_valid && m_axis_tlast && (beat_cnt < 2'd2);
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



// ip_metadata_assembler
// Combines the fields captured above with the result of the header checksum
// verifier into the packed 110-bit metadata word the IP parser hands to
// whatever sits above it.

module ip_metadata_assembler (
    input  logic        clk,
    input  logic        rst_n,

    // AXI-Stream pass-through signals, just for end-of-packet timing
    input  logic         tvalid,
    input  logic         tready,
    input  logic         tlast,

    // From the header capture module above
    input  logic [31:0] src_ip,
    input  logic [31:0] dst_ip,
    input  logic [15:0] total_len,
    input  logic [7:0]  protocol,
    input  logic [7:0]  ttl,
    input  logic [5:0]  dscp,
    input  logic [1:0]  ecn,
    input  logic [3:0]  ihl,
    input  logic        capture_done,
    input  logic        header_incomplete,

    // From the header checksum verifier
    input  logic        checksum_ok,
    input  logic        checksum_valid,

    // Packed output
    output logic [109:0] metadata,
    output logic          metadata_valid,
    output logic          assembly_incomplete
);

    logic [31:0] src_ip_r, dst_ip_r;
    logic [15:0] total_len_r;
    logic [7:0]  protocol_r, ttl_r;
    logic [5:0]  dscp_r;
    logic [1:0]  ecn_r;
    logic [3:0]  ihl_r;
    logic        checksum_ok_r;

    logic have_fields, have_checksum;
    logic tlast_pending; // saw tlast on a complete header, still waiting on dst_ip and/or checksum

    logic beat_fire;
    assign beat_fire = tvalid && tready;

   
    logic capture_done_d;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) capture_done_d <= 1'b0;
        else        capture_done_d <= capture_done;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            src_ip_r            <= 32'd0;
            dst_ip_r            <= 32'd0;
            total_len_r         <= 16'd0;
            protocol_r          <= 8'd0;
            ttl_r                <= 8'd0;
            dscp_r               <= 6'd0;
            ecn_r                <= 2'd0;
            ihl_r                <= 4'd0;
            checksum_ok_r        <= 1'b0;
            have_fields          <= 1'b0;
            have_checksum        <= 1'b0;
            tlast_pending        <= 1'b0;
            metadata             <= 110'd0;
            metadata_valid       <= 1'b0;
            assembly_incomplete  <= 1'b0;
        end else begin
            metadata_valid      <= 1'b0; // defaults, pulses below
            assembly_incomplete <= 1'b0;

            
            if (beat_fire && capture_done) begin
                total_len_r <= total_len;
                protocol_r  <= protocol;
                ttl_r       <= ttl;
                dscp_r      <= dscp;
                ecn_r       <= ecn;
                ihl_r       <= ihl;
                src_ip_r    <= src_ip;
            end

            
            if (capture_done_d) begin
                dst_ip_r    <= dst_ip;
                have_fields <= 1'b1;
            end

            
            if (beat_fire && checksum_valid) begin
                checksum_ok_r <= checksum_ok;
                have_checksum <= 1'b1;
            end

            if (beat_fire && header_incomplete) begin
                
                metadata <= { src_ip_r, dst_ip_r, total_len_r, protocol_r,
                              ttl_r, dscp_r, ecn_r, ihl_r, checksum_ok_r,
                              1'b0 }; 
                metadata_valid      <= 1'b1;
                assembly_incomplete <= 1'b1;
                have_fields    <= 1'b0;
                have_checksum  <= 1'b0;
                tlast_pending  <= 1'b0;
            end else if (beat_fire && tlast) begin
                if (have_fields && have_checksum) begin
                    // dst_ip and checksum already latched -- safe to emit now
                    metadata <= { src_ip_r, dst_ip_r, total_len_r, protocol_r,
                                  ttl_r, dscp_r, ecn_r, ihl_r,
                                  (checksum_valid ? checksum_ok : checksum_ok_r),
                                  1'b1 };
                    metadata_valid <= 1'b1;
                    have_fields    <= 1'b0;
                    have_checksum  <= 1'b0;
                end else begin
                    
                    tlast_pending <= 1'b1;
                end
            end else if (tlast_pending && have_fields && have_checksum) begin
                
                metadata <= { src_ip_r, dst_ip_r, total_len_r, protocol_r,
                              ttl_r, dscp_r, ecn_r, ihl_r, checksum_ok_r, 1'b1 };
                metadata_valid <= 1'b1;
                have_fields    <= 1'b0;
                have_checksum  <= 1'b0;
                tlast_pending  <= 1'b0;
            end
        end
    end

endmodule



// ip_header_parser_top
// Wires the header extractor straight into the metadata assembler

module ip_header_parser_top (
    input   logic        clk,
    input   logic        rst_n,

    input   logic [63:0] m_axis_tdata,
    input   logic [7:0]  m_axis_tkeep,
    input   logic        m_axis_tvalid,
    output  logic        m_axis_tready,
    input   logic        m_axis_tlast,
    input   logic [0:0]  m_axis_tuser,

    // placeholder until the checksum verifier module exists
    input   logic        checksum_ok,
    input   logic        checksum_valid,

    output  logic [109:0] metadata,
    output  logic          metadata_valid,
    output  logic          assembly_incomplete
);

    // wires carrying fields from the extractor to the assembler
    logic [3:0]  version;   // unused by the assembler, extractor still produces it
    logic [3:0]  ihl;
    logic [5:0]  dscp;
    logic [1:0]  ecn;
    logic [15:0] total_len;
    logic [7:0]  ttl;
    logic [7:0]  protocol;
    logic [31:0] src_ip;
    logic [31:0] dst_ip;
    logic        capture_done;
    logic        header_incomplete;

    ip_parser_header_extraction u_extract (
        .clk               (clk),
        .rst_n             (rst_n),
        .m_axis_tdata      (m_axis_tdata),
        .m_axis_tkeep      (m_axis_tkeep),
        .m_axis_tvalid     (m_axis_tvalid),
        .m_axis_tready     (m_axis_tready),
        .m_axis_tlast      (m_axis_tlast),
        .m_axis_tuser      (m_axis_tuser),
        .capture_done      (capture_done),
        .header_incomplete (header_incomplete),
        .version           (version),
        .ihl               (ihl),
        .dscp              (dscp),
        .ecn               (ecn),
        .total_len         (total_len),
        .ttl               (ttl),
        .protocol          (protocol),
        .src_ip            (src_ip),
        .dst_ip            (dst_ip)
    );

    ip_metadata_assembler u_assemble (
        .clk                 (clk),
        .rst_n               (rst_n),
        .tvalid              (m_axis_tvalid),
        .tready              (m_axis_tready),
        .tlast               (m_axis_tlast),
        .src_ip              (src_ip),
        .dst_ip              (dst_ip),
        .total_len           (total_len),
        .protocol            (protocol),
        .ttl                 (ttl),
        .dscp                (dscp),
        .ecn                 (ecn),
        .ihl                 (ihl),
        .capture_done        (capture_done),
        .header_incomplete   (header_incomplete),
        .checksum_ok         (checksum_ok),
        .checksum_valid      (checksum_valid),
        .metadata            (metadata),
        .metadata_valid      (metadata_valid),
        .assembly_incomplete (assembly_incomplete)
    );

endmodule
