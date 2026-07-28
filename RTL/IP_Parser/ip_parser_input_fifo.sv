`timescale 1ns / 1ps

module ip_parser_input_fifo # (
    parameter DEPTH = 512,                      // Max num of words
    parameter ADDRW = $clog2(DEPTH)             // Num of bits needed
)(
    input   logic           clk,
    input   logic           rst_n,

    // Write Interface (From the Frame Parser)
    input   logic [63:0]    s_axis_tdata,       // 8 bytes of packet data per clock cycle, starting at byte 0 of the IP header. Big-endian, matching wire order.
    input   logic [7:0]     s_axis_tkeep,       // Valid byte mask. 0xFF on all beats except the last, where it indicates how many trailing bytes are real data.
    input   logic           s_axis_tvalid,      // Data is valid and ready to be consumed.
    output  logic           s_axis_tready,      // Backpressure from the IP parser back upstream. If low, upstream must hold data stable.
    input   logic           s_axis_tlast,       // High on the final beat of the packet.
    input   logic [0:0]     s_axis_tuser,       // FCS error flag propagated from the MAC. If high, the frame had a bad CRC and should be discarded here too.

    // Read Interface (To IP Parser logic)
    output  logic [63:0]    m_axis_tdata,
    output  logic [7:0]     m_axis_tkeep,
    output  logic           m_axis_tvalid,
    input   logic           m_axis_tready,
    output  logic           m_axis_tlast,
    output  logic [0:0]     m_axis_tuser
);

// Internal Signal Packing
localparam DATAW = 64 + 8 + 1 + 1;              // tdata + tkeep + tlast + tuser
logic [DATAW-1:0] write_word;
logic [DATAW-1:0] read_word;

assign write_word = {s_axis_tuser, s_axis_tlast, s_axis_tkeep, s_axis_tdata};   // Bundles into a single 74-bit cable
assign {m_axis_tuser, m_axis_tlast, m_axis_tkeep, m_axis_tdata} = read_word;    // Splits 74-bit into individual wires

// Interface Memory and Pointers
logic [DATAW-1:0] mem [0:DEPTH-1];              // Builds RAM block 74 bits wide and 512 entries deep
logic [ADDRW-1:0] rd_ptr, wr_ptr;               // Addresses to row to write/read to
logic [ADDRW:0] occupancy;

// Handshaking and Backpressure Logic
logic full, empty, push, pop;
logic read_en, valid_r;

assign push = s_axis_tvalid && s_axis_tready;
assign pop  = m_axis_tvalid && m_axis_tready;

assign full  = (occupancy == DEPTH);
assign empty = (occupancy == 0);

// First-Word Fall-Through (Using BRAM)
assign read_en = ~empty && (~valid_r || pop);

// tready goes high if fifo isn't full, or if we are making room by fetching from BRAM this cycle
assign s_axis_tready = ~full || read_en;
assign m_axis_tvalid = valid_r;

always_ff @(posedge clk) begin
    if (push) begin
        mem[wr_ptr] <= write_word;
    end
    if (read_en) begin
        if (push && (wr_ptr == rd_ptr)) begin
            // COLLISION CASE: Writing and reading the same address.
            // Because of Non-Blocking Assignment (<=) rules in simulation, 
            // mem[rd_ptr] is sampled BEFORE the 'push' write actually commits.
            // This forces the simulator to read the OLD data.
            read_word <= mem[rd_ptr];
        end else begin
            // NORMAL CASE: Reading a different address.
            read_word <= mem[rd_ptr];
        end
    end
end

// Synchronous Block (Made from DFFs)
always_ff @(posedge clk or negedge rst_n) begin
    // Reset condition
    if (!rst_n) begin
        rd_ptr      <= 'd0;
        wr_ptr      <= 'd0;
        occupancy   <= 'd0;
        valid_r     <= 1'b0;
    end else begin
        // Output validity tracking
        if (read_en)      valid_r <= 1'b1;
        else if (pop)     valid_r <= 1'b0;

        // Push & BRAM Read simultaneously (Occupancy doesn't change here)
        if (push && read_en) begin
            wr_ptr <= wr_ptr + 1;
            rd_ptr <= rd_ptr + 1;
        end
        // Push only
        else if (push) begin
            wr_ptr      <= wr_ptr + 1;
            occupancy   <= occupancy + 1;
        end
        // BRAM Read only
        else if (read_en) begin
            rd_ptr      <= rd_ptr + 1;
            occupancy   <= occupancy - 1;
        end
    end
end

endmodule
