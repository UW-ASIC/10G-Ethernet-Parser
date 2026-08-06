

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
