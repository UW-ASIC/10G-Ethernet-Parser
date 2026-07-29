`timescale 1ns / 1ps

// ============================================================================
// ip_parser_ihl_decoder
// It's whole purpose is to find out how long the IP header is
// and to produce byte-level boundary for payload stripper
//
// I think for this IP parser is supposed to be a fixed 20-byte (ihl=5)
// just based of how the checksum module is hardcoded to summ exactly 20 bytes
// and that if any packet with ihl > 5 (i.e. options are present)
// only the first 20 bytes are checked against a checksum the sender computed.

module ip_parser_ihl_decoder (
    input  logic [3:0] ihl,

    output logic [5:0] header_len_bytes,     // ihl * 4
    output logic [2:0] header_end_beat,      // beat containing the header/payload split
    output logic [2:0] header_end_offset,    // byte offset within that beat
    output logic       ihl_invalid           // ihl != 5
);

    assign header_len_bytes  = {ihl, 2'b00};            // Same thing as ihl * 4
    assign header_end_beat   = header_len_bytes[5:3];   // Same thing as header_len_bytes / 8
    assign header_end_offset = header_len_bytes[2:0];   // Same thing as header_len_bytes % 8

    assign ihl_invalid       = (ihl != 4'd5);
endmodule
