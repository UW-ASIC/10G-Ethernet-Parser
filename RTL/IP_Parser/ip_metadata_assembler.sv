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

            
            // capture_done is already registered on the extractor side to land
            // on the same cycle dst_ip is actually valid, so it's safe to grab
            // everything (including dst_ip) off one pulse - no beat_fire gating
            // needed here, capture_done was already qualified by it upstream
            if (capture_done) begin
                total_len_r <= total_len;
                protocol_r  <= protocol;
                ttl_r       <= ttl;
                dscp_r      <= dscp;
                ecn_r       <= ecn;
                ihl_r       <= ihl;
                src_ip_r    <= src_ip;
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

