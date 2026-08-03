`ifndef ETH_FRAME_PKG_SV
`define ETH_FRAME_PKG_SV

// shared verification utilities for PCS testbenches.
// include this in your tb: `include "eth_frame_pkg.sv"
//
// this file gives you a starting point for generating and checking PCS traffic.
// if you need a task that doesn't exist here, add it and use it. the idea is that
// everyone builds on a common set of helpers rather than reinventing stimulus
// generation in every testbench.
//
// *: the PCS has no awareness of ethernet frame structure (MAC headers, ethertype,
//    FCS, etc). it only sees XGMII beats: start characters, opaque data bytes,
//    terminate characters, and idle characters. the utilities here reflect that —
//    payload bytes are random and unstructured. thus frame-level semantics are the
//    MAC's problem, not ours.

package eth_frame_pkg;

    localparam DATA_W = 64;
    localparam HEAD_W = 2;
    localparam BLOCK_W = DATA_W + HEAD_W;
    localparam CTRL_W = 7;
    localparam BLOCK_TYPE_W = 8;
    localparam KEEP_W = DATA_W / 8;

    // sync headers
    localparam [1:0] SYNC_DATA = 2'b01;
    localparam [1:0] SYNC_CTRL = 2'b10;

    // XGMII special characters
    localparam [7:0] XGMII_IDLE  = 8'h07;
    localparam [7:0] XGMII_START = 8'hFB;
    localparam [7:0] XGMII_TERM  = 8'hFD;
    localparam [7:0] XGMII_ERROR = 8'hFE;

    // block type codes (clause 49 figure 49-7)
    localparam [BLOCK_TYPE_W-1:0]
        BT_CTRL   = 8'h1e,
        BT_START  = 8'h78,
        BT_TERM_0 = 8'h87,
        BT_TERM_1 = 8'h99,
        BT_TERM_2 = 8'haa,
        BT_TERM_3 = 8'hb4,
        BT_TERM_4 = 8'hcc,
        BT_TERM_5 = 8'hd2,
        BT_TERM_6 = 8'he1,
        BT_TERM_7 = 8'hff;

    // idle control code: XGMII 0x07 -> 7-bit code 0x00
    localparam [CTRL_W-1:0] CTRL_IDLE = 7'h00;

    // --------------------------------------------------------------------------
    // payload storage. just a byte array + length.
    // the PCS doesn't care what's inside; could be a valid ethernet frame,
    // could be all 0xAA. Doesn't concern us since we're testing encoding/scrambling/gearboxing.
    // --------------------------------------------------------------------------
    typedef struct {
        logic [7:0] bytes [0:1599];
        int         len;
    } payload_t;

    // --------------------------------------------------------------------------
    // generate a random payload of a given byte length.
    // if len is -1, picks a random length between 46 and 1500.
    // --------------------------------------------------------------------------
    function automatic payload_t gen_random_payload(int len = -1);
        payload_t p;
        p.len = (len < 0) ? $urandom_range(46, 1500) : len;
        for (int i = 0; i < p.len; i++)
            p.bytes[i] = $urandom;
        return p;
    endfunction

    // --------------------------------------------------------------------------
    // XGMII beat: the representation the encoder consumes and the decoder produces.
    // --------------------------------------------------------------------------
    typedef struct {
        logic [DATA_W-1:0]  data;
        logic [KEEP_W-1:0]  ctrl;
        logic [KEEP_W-1:0]  keep;
        logic               start;
        logic               terminate;
        logic               idle;
    } xgmii_beat_t;

    // --------------------------------------------------------------------------
    // build XGMII beat sequences from a payload.
    //
    // beat layout:
    //   beat 0: start beat -> data[0] = 0xFB (start char), data[7:1] = first 7 payload bytes
    //   beat 1..N-1: data beats —> 8 payload bytes each
    //   beat N: terminate beat —> remaining bytes + 0xFD (terminate char) + idle padding
    //
    // the terminate position depends on how many bytes are left after the last
    // full data beat. this determines which TERM_x block type the encoder should
    // select, and what o_keep the decoder should produce.
    //
    // *: o_keep on terminate beats marks only the valid DATA bytes, not the
    //    terminate character itself. o_terminate already tells the MAC a terminate
    //    is present. if your encoder/decoder disagree on this, that's a bug.
    //
    // returns the number of beats generated.
    // --------------------------------------------------------------------------
    function automatic int build_xgmii_beats(
        input  payload_t      payload,
        output xgmii_beat_t   beats [0:255]
    );
        int beat_idx = 0;
        int byte_idx = 0;
        int remaining;

        // start beat: 0xFB + first 7 payload bytes
        beats[0].data[7:0]  = XGMII_START;
        beats[0].ctrl       = 8'h01;
        beats[0].keep       = 8'hFF;
        beats[0].start      = 1'b1;
        beats[0].terminate  = 1'b0;
        beats[0].idle       = 1'b0;
        for (int i = 1; i < 8; i++) begin
            if (byte_idx < payload.len)
                beats[0].data[i*8 +: 8] = payload.bytes[byte_idx++];
            else
                beats[0].data[i*8 +: 8] = XGMII_IDLE;
        end
        beat_idx++;

        // data + terminate beats
        while (byte_idx < payload.len) begin
            remaining = payload.len - byte_idx;
            if (remaining >= 8) begin
                // full data beat
                for (int i = 0; i < 8; i++)
                    beats[beat_idx].data[i*8 +: 8] = payload.bytes[byte_idx++];
                beats[beat_idx].ctrl      = 8'h00;
                beats[beat_idx].keep      = 8'hFF;
                beats[beat_idx].start     = 1'b0;
                beats[beat_idx].terminate = 1'b0;
                beats[beat_idx].idle      = 1'b0;
                beat_idx++;
            end else begin
                // terminate beat: remaining data + terminate char + idle padding
                beats[beat_idx].ctrl = 8'h00;
                beats[beat_idx].keep = 8'h00;
                for (int i = 0; i < 8; i++) begin
                    if (i < remaining) begin
                        beats[beat_idx].data[i*8 +: 8] = payload.bytes[byte_idx++];
                    end else if (i == remaining) begin
                        beats[beat_idx].data[i*8 +: 8] = XGMII_TERM;
                        beats[beat_idx].ctrl[i] = 1'b1;
                    end else begin
                        beats[beat_idx].data[i*8 +: 8] = XGMII_IDLE;
                        beats[beat_idx].ctrl[i] = 1'b1;
                    end
                end
                // keep marks only valid data bytes (not the terminate character)
                for (int i = 0; i < remaining; i++)
                    beats[beat_idx].keep[i] = 1'b1;
                beats[beat_idx].start     = 1'b0;
                beats[beat_idx].terminate = 1'b1;
                beats[beat_idx].idle      = 1'b0;
                beat_idx++;
            end
        end

        // if payload ended exactly on a beat boundary, need a standalone terminate beat
        if ((payload.len % 7) == 0 && beat_idx > 0 && !beats[beat_idx-1].terminate) begin
            beats[beat_idx].data[7:0]  = XGMII_TERM;
            for (int i = 1; i < 8; i++)
                beats[beat_idx].data[i*8 +: 8] = XGMII_IDLE;
            beats[beat_idx].ctrl      = 8'hFF;
            beats[beat_idx].keep      = 8'h00;
            beats[beat_idx].start     = 1'b0;
            beats[beat_idx].terminate = 1'b1;
            beats[beat_idx].idle      = 1'b0;
            beat_idx++;
        end

        return beat_idx;
    endfunction

    // --------------------------------------------------------------------------
    // generate an all-idle XGMII beat (8 x 0x07, ctrl = 0xFF)
    // --------------------------------------------------------------------------
    function automatic xgmii_beat_t idle_beat();
        xgmii_beat_t b;
        b.data      = 64'h0707070707070707;
        b.ctrl      = 8'hFF;
        b.keep      = 8'hFF;
        b.start     = 1'b0;
        b.terminate = 1'b0;
        b.idle      = 1'b1;
        return b;
    endfunction

    // --------------------------------------------------------------------------
    // build a 66-bit idle control block (block type 0x1E, all idle codes)
    // useful for driving scrambler/descrambler/gearbox directly
    // --------------------------------------------------------------------------
    function automatic logic [BLOCK_W-1:0] idle_block();
        logic [BLOCK_W-1:0] blk;
        blk[1:0] = SYNC_CTRL;
        blk[9:2] = BT_CTRL;
        for (int i = 0; i < 8; i++)
            blk[10 + i*7 +: 7] = CTRL_IDLE;
        return blk;
    endfunction

    // --------------------------------------------------------------------------
    // build a 66-bit data block from 8 random bytes
    // --------------------------------------------------------------------------
    function automatic logic [BLOCK_W-1:0] random_data_block();
        logic [BLOCK_W-1:0] blk;
        blk[1:0] = SYNC_DATA;
        for (int i = 0; i < 8; i++)
            blk[2 + i*8 +: 8] = $urandom;
        return blk;
    endfunction

    // --------------------------------------------------------------------------
    // compare two 64-bit values with a descriptive message on mismatch
    // --------------------------------------------------------------------------
    function automatic logic check_match(
        input logic [63:0] expected,
        input logic [63:0] actual,
        input string       label
    );
        if (expected !== actual) begin
            $display("  FAIL [%s]: expected %h, got %h", label, expected, actual);
            return 1'b0;
        end
        return 1'b1;
    endfunction

endpackage

`endif