`timescale 1ns / 1ps
// iverilog 13 cannot compile eth_frame_pkg.sv (unpacked structs unsupported).
// nothing here needs the package, so skip it under icarus.
`ifndef __ICARUS__
`include "eth_frame_pkg.sv"
`endif

module rx_path_tb;

`ifndef __ICARUS__
    import eth_frame_pkg::*;
`endif

    localparam DATA_W  = 64;
    localparam HEAD_W  = 2;
    localparam BLOCK_W = DATA_W + HEAD_W;

    localparam int MAX_BEATS = 256;    // beats in one frame
    localparam int MAX_EXP   = 1024;   // driven beats logged for comparison
    localparam int MAX_CAP   = 2048;   // decoder beats captured

    logic clk;
    logic rst_n;

    // SerDes input (driven by tb, via the tx stimulus generator below)
    logic [DATA_W - 1 : 0]  serdes_data;
    logic                   serdes_valid;

    // MAC RX output (checked by tb)
    logic                      o_valid;
    logic [DATA_W - 1 : 0]     o_data;
    logic [DATA_W/8 - 1 : 0]   o_ctrl;
    logic [DATA_W/8 - 1 : 0]   o_keep;
    logic                      o_start;
    logic                      o_idle;
    logic                      o_terminate;
    logic                      o_error;

    // internal interconnect signals (directly wired)
    logic [BLOCK_W - 1 : 0]   gearbox_block;
    logic                      gearbox_valid;
    logic [HEAD_W - 1 : 0]    gearbox_head;
    logic                      sync_slip;
    logic                      sync_lock;
    logic                      descram_valid;
    logic [DATA_W + 1 : 0]    descram_data;

    // --------------------------------------------------------------------------
    // full RX path: gearbox_rx -> block_sync + descrambler -> decoder
    //
    // interconnect:
    //   gearbox_rx outputs: o_data (66-bit block), o_valid, o_head
    //   block_sync inputs: i_valid (from gearbox), i_head (from gearbox), i_serdes_v
    //   block_sync outputs: o_slip (to gearbox), o_lock
    //   descrambler inputs: i_valid (from gearbox), i_scram_data (from gearbox o_data)
    //   descrambler outputs: o_valid, o_descram_data (66-bit)
    //   decoder inputs: i_valid (from descrambler), i_data (from descrambler)
    //   decoder outputs: all XGMII signals
    //
    // *: block_sync and the descrambler both consume gearbox output.
    //    block_sync only needs the header, descrambler needs the full block.
    //    they run in parallel— block_sync doesn't gate the descrambler.
    //
    // *: should the descrambler be gated by sync_lock? in our design it isn't;
    //    it processes everything the gearbox produces, even before lock.
    //    the decoder will flag errors on misaligned blocks via o_error.
    //    think about whether this is the right choice.
    //
    // ANSWER (test 1 + test 4 evidence): during acquisition it costs 190 spurious
    // o_error pulses and nothing else. during a SERDES DROPOUT it is a real defect:
    // gearbox_rx freezes instead of clearing o_valid, so stale blocks reach the MAC
    // flagged valid. see test 4 check 3.
    // --------------------------------------------------------------------------

    // --------------------------------------------------------------------------
    // remote TX stimulus generator
    //
    //   tests 1/2/4:  tb drives tx_block directly       (use_encoder = 0)
    //   tests 3/5/6:  tb drives XGMII beats -> encoder  (use_encoder = 1)
    //
    // full chain: [beats ->] encoder -> scrambler -> gearbox_tx -> serdes_data
    //
    // scrambling is required, not cosmetic. an unscrambled idle stream repeats
    // every 66 bits, and offsets 1, 2 and 6 into that pattern yield a valid-looking
    // sync header on EVERY block -> block_sync counts 64 in a row and false-locks
    // at the wrong alignment. scrambled payload makes a wrong offset produce ~50%
    // bad headers, so only the true alignment can accumulate 64 good headers.
    //
    // tx_valid = tx_accept holds the block whenever the tx gearbox is full
    // (1 cycle in 33). the scrambler's state only advances on i_valid, so the same
    // block is re-presented and consumed on the next cycle.
    // --------------------------------------------------------------------------
    logic [BLOCK_W - 1 : 0] tx_block;        // direct block source (tests 1/2/4)
    logic [BLOCK_W - 1 : 0] tx_enc_block;    // encoder output    (tests 3/5/6)
    logic                    tx_enc_valid;
    logic [BLOCK_W - 1 : 0] tx_scram_in;
    logic                    use_encoder;
    logic                    tx_valid;
    logic [BLOCK_W - 1 : 0] tx_scram_data;
    logic                    tx_scram_valid;
    logic [DATA_W - 1 : 0]  tx_serdes_data;
    logic                    tx_accept;
    logic [DATA_W - 1 : 0]  inject_mask;     // test 6 bit-error injection

    // XGMII beat presented to the encoder
    logic                    xg_valid;
    logic [DATA_W - 1 : 0]  xg_data;
    logic [7:0]              xg_ctrl;
    logic [7:0]              xg_keep;
    logic                    xg_start;
    logic                    xg_idle;
    logic                    xg_terminate;
    logic                    xg_error;

    assign tx_valid    = tx_accept;
    assign tx_scram_in = use_encoder ? tx_enc_block : tx_block;

    encoder #(.DATA_W(DATA_W)) u_tx_encoder (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_valid     (xg_valid),
        .i_data      (xg_data),
        .i_ctrl      (xg_ctrl),
        .i_keep      (xg_keep),
        .i_start     (xg_start),
        .i_idle      (xg_idle),
        .i_terminate (xg_terminate),
        .i_error     (xg_error),
        .o_valid     (tx_enc_valid),
        .o_data      (tx_enc_block)
    );

    scrambler #(.DATA_W(DATA_W)) u_tx_scrambler (
        .clk          (clk),
        .rst_n        (rst_n),
        .i_valid      (tx_valid),
        .i_enc_data   (tx_scram_in),
        .o_valid      (tx_scram_valid),
        .o_scram_data (tx_scram_data)
    );

    gearbox_tx #(.DATA_W(DATA_W), .HEAD_W(HEAD_W)) u_tx_gearbox (
        .clk      (clk),
        .rst_n    (rst_n),
        .i_head   (tx_scram_data[1:0]),
        .i_data   (tx_scram_data[BLOCK_W-1:2]),
        .o_data   (tx_serdes_data),
        .o_accept (tx_accept)
    );

    // inject_mask is '0 except for the single corrupted cycle in test 6
    assign serdes_data = tx_serdes_data ^ inject_mask;

    // the RX path itself
    gearbox_rx #(.DATA_W(DATA_W), .HEAD_W(HEAD_W)) u_gearbox_rx (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_data     (serdes_data),
        .i_pma_lock (serdes_valid),
        .i_slip     (sync_slip),
        .o_data     (gearbox_block),
        .o_valid    (gearbox_valid),
        .o_head     (gearbox_head)
    );

    block_sync_rx #(.HEAD_W(HEAD_W)) u_block_sync (
        .clk        (clk),
        .rst_n      (rst_n),
        .i_serdes_v (serdes_valid),
        .i_valid    (gearbox_valid),
        .i_head     (gearbox_head),
        .o_slip     (sync_slip),
        .o_lock     (sync_lock)
    );

    descrambler #(.DATA_W(DATA_W)) u_descrambler (
        .clk            (clk),
        .rst_n          (rst_n),
        .i_valid        (gearbox_valid),
        .i_scram_data   (gearbox_block),
        .o_valid        (descram_valid),
        .o_descram_data (descram_data)
    );

    decoder #(.DATA_W(DATA_W)) u_decoder (
        .clk         (clk),
        .rst_n       (rst_n),
        .i_valid     (descram_valid),
        .i_data      (descram_data),
        .o_valid     (o_valid),
        .o_data      (o_data),
        .o_ctrl      (o_ctrl),
        .o_keep      (o_keep),
        .o_start     (o_start),
        .o_idle      (o_idle),
        .o_terminate (o_terminate),
        .o_error     (o_error)
    );

    // 156.25 MHz
    initial clk = 0;
    always #3.2 clk = ~clk;

    int pass_count, fail_count;

    // 66-bit all-idle control block: sync = 10, block type = 0x1e, 8 x idle code 0x00
    // (same as eth_frame_pkg::idle_block(), duplicated so the tb builds under icarus)
    function automatic logic [BLOCK_W - 1 : 0] rx_idle_block();
        logic [BLOCK_W - 1 : 0] blk;
        blk      = '0;
        blk[1:0] = 2'b10;
        blk[9:2] = 8'h1e;
        return blk;
    endfunction

    // park the encoder inputs on a valid idle beat
    task automatic clear_xgmii_idle();
        begin
            xg_valid     = 1'b1;
            xg_data      = 64'h0707070707070707;
            xg_ctrl      = 8'hFF;
            xg_keep      = 8'hFF;
            xg_start     = 1'b0;
            xg_terminate = 1'b0;
            xg_idle      = 1'b1;
            xg_error     = 1'b0;
        end
    endtask

    task automatic do_reset();
        rst_n        = 0;
        // NOTE: serdes_data is continuously driven by u_tx_gearbox, so it can't be
        // assigned procedurally here. the tx gearbox shares rst_n, so its output is
        // already 0 while reset is held.
        serdes_valid = 0;
        @(posedge clk);
        @(posedge clk);
        rst_n = 1;
    endtask

    // --------------------------------------------------------------------------
    // to test the RX path, you need to generate a realistic SerDes input stream.
    // this means: take 66-bit blocks, SCRAMBLE them (the remote TX does this),
    // then pack them into 64-bit words (as if gearbox_tx did it on the other end).
    //
    // two approaches:
    //   a) instantiate a scrambler + gearbox_tx in the tb to generate the stream.
    //      this is the most realistic but means you're testing with modules that
    //      may have their own bugs.
    //   b) build the stream manually: construct 66-bit blocks, XOR them with a
    //      known LFSR sequence, pack into 64-bit words. more work but fully
    //      controlled.
    //
    // *: approach (a) is recommended for integration testing. if the TX path
    //    works (verified by tx_path_tb), it's a valid stimulus generator.
    //    approach (b) is better for debugging specific RX issues in isolation.
    //
    // for initial bring-up, you can skip scrambling entirely: feed unscrambled
    // blocks. the descrambler will output garbage for the first ~1 block while
    // its LFSR converges, but after that it should recover. this lets you test
    // gearbox + block_sync without worrying about scrambling correctness.
    //
    // CHOSEN: approach (a). do NOT skip scrambling — an unscrambled idle stream
    // lets block_sync false-lock at the wrong offset (the 66-bit idle pattern has
    // offsets 1, 2 and 6 that look like valid headers on every single block), so
    // the test would pass for the wrong reason.
    // --------------------------------------------------------------------------

    // --------------------------------------------------------------------------
    // XGMII beat construction (local replacement for eth_frame_pkg::build_xgmii_beats,
    // which is unreachable under icarus). parallel arrays instead of a struct array.
    //
    // deviation from the package version: its trailing standalone-terminate guard is
    // (len % 7) == 0, which is wrong. beat 0 carries 7 payload bytes and every later
    // beat carries 8, so the payload lands exactly on a beat boundary when
    // len == 7 (mod 8). this version instead emits a standalone terminate beat
    // whenever the loop ended without one, which is correct for every length.
    // --------------------------------------------------------------------------
    logic [DATA_W - 1 : 0] beat_data  [0:MAX_BEATS-1];
    logic [7:0]            beat_ctrl  [0:MAX_BEATS-1];
    logic [7:0]            beat_keep  [0:MAX_BEATS-1];
    bit                    beat_start [0:MAX_BEATS-1];
    bit                    beat_term  [0:MAX_BEATS-1];
    int                    beat_count;

    logic [7:0] payload_bytes [0:1599];
    int         payload_len;

    task automatic rx_build_xgmii_beats();
        int byte_idx;
        int remaining;
        int i;
        logic [DATA_W - 1 : 0] d;
        logic [7:0]            c;
        logic [7:0]            k;
        begin
            beat_count = 0;
            byte_idx   = 0;

            // start beat: 0xFB + first 7 payload bytes
            d      = '0;
            d[7:0] = 8'hFB;
            for (i = 1; i < 8; i++) begin
                if (byte_idx < payload_len) begin
                    d[i*8 +: 8] = payload_bytes[byte_idx];
                    byte_idx    = byte_idx + 1;
                end else begin
                    d[i*8 +: 8] = 8'h07;
                end
            end
            beat_data[beat_count]  = d;
            beat_ctrl[beat_count]  = 8'h01;
            beat_keep[beat_count]  = 8'hFF;
            beat_start[beat_count] = 1'b1;
            beat_term[beat_count]  = 1'b0;
            beat_count = beat_count + 1;

            // data + terminate beats
            while (byte_idx < payload_len && beat_count < MAX_BEATS) begin
                remaining = payload_len - byte_idx;
                if (remaining >= 8) begin
                    d = '0;
                    for (i = 0; i < 8; i++) begin
                        d[i*8 +: 8] = payload_bytes[byte_idx];
                        byte_idx    = byte_idx + 1;
                    end
                    beat_data[beat_count]  = d;
                    beat_ctrl[beat_count]  = 8'h00;
                    beat_keep[beat_count]  = 8'hFF;
                    beat_start[beat_count] = 1'b0;
                    beat_term[beat_count]  = 1'b0;
                    beat_count = beat_count + 1;
                end else begin
                    // remaining data bytes, then 0xFD, then idle padding.
                    // keep marks only the DATA bytes, so keep+1 is one-hot at the
                    // terminate position, which is exactly the encoder's term_pos.
                    d = '0;
                    c = 8'h00;
                    k = 8'h00;
                    for (i = 0; i < 8; i++) begin
                        if (i < remaining) begin
                            d[i*8 +: 8] = payload_bytes[byte_idx];
                            byte_idx    = byte_idx + 1;
                            k[i]        = 1'b1;
                        end else if (i == remaining) begin
                            d[i*8 +: 8] = 8'hFD;
                            c[i]        = 1'b1;
                        end else begin
                            d[i*8 +: 8] = 8'h07;
                            c[i]        = 1'b1;
                        end
                    end
                    beat_data[beat_count]  = d;
                    beat_ctrl[beat_count]  = c;
                    beat_keep[beat_count]  = k;
                    beat_start[beat_count] = 1'b0;
                    beat_term[beat_count]  = 1'b1;
                    beat_count = beat_count + 1;
                end
            end

            // payload ended on a beat boundary -> standalone terminate beat (TERM_0)
            if (beat_count > 0 && !beat_term[beat_count-1] && beat_count < MAX_BEATS) begin
                d      = '0;
                d[7:0] = 8'hFD;
                for (i = 1; i < 8; i++) d[i*8 +: 8] = 8'h07;
                beat_data[beat_count]  = d;
                beat_ctrl[beat_count]  = 8'hFF;
                beat_keep[beat_count]  = 8'h00;
                beat_start[beat_count] = 1'b0;
                beat_term[beat_count]  = 1'b1;
                beat_count = beat_count + 1;
            end
        end
    endtask

    // deterministic payload, so a failure is reproducible. swap in $urandom if you
    // want randomised traffic.
    task automatic make_payload(input int len, input int seed);
        int i;
        begin
            payload_len = len;
            for (i = 0; i < len; i++)
                payload_bytes[i] = (i * 7 + seed * 31) & 8'hFF;
        end
    endtask

    // --------------------------------------------------------------------------
    // beat driving, honouring gearbox_tx backpressure.
    //
    // reading tx_accept immediately after @(posedge clk) yields its PRE-edge value,
    // i.e. "was the presented block consumed at that edge". so: present, wait an
    // edge, and keep holding until an edge where it was accepted.
    // --------------------------------------------------------------------------
    task automatic drive_beat(input int idx);
        begin
            xg_valid     = 1'b1;
            xg_data      = beat_data[idx];
            xg_ctrl      = beat_ctrl[idx];
            xg_keep      = beat_keep[idx];
            xg_start     = beat_start[idx];
            xg_terminate = beat_term[idx];
            xg_idle      = 1'b0;
            xg_error     = 1'b0;
            @(posedge clk);
            while (!tx_accept) @(posedge clk);
        end
    endtask

    task automatic drive_idle_beat();
        begin
            clear_xgmii_idle();
            @(posedge clk);
            while (!tx_accept) @(posedge clk);
        end
    endtask

    // driven-beat log, for comparing the whole stream in test 5
    logic [DATA_W - 1 : 0] exp_data  [0:MAX_EXP-1];
    logic [7:0]            exp_ctrl  [0:MAX_EXP-1];
    logic [7:0]            exp_keep  [0:MAX_EXP-1];
    bit                    exp_start [0:MAX_EXP-1];
    bit                    exp_term  [0:MAX_EXP-1];
    int                    exp_count;

    task automatic send_and_log_beat(input int idx);
        begin
            if (exp_count < MAX_EXP) begin
                exp_data[exp_count]  = beat_data[idx];
                exp_ctrl[exp_count]  = beat_ctrl[idx];
                exp_keep[exp_count]  = beat_keep[idx];
                exp_start[exp_count] = beat_start[idx];
                exp_term[exp_count]  = beat_term[idx];
                exp_count = exp_count + 1;
            end
            drive_beat(idx);
        end
    endtask

    task automatic send_and_log_idle();
        begin
            if (exp_count < MAX_EXP) begin
                exp_data[exp_count]  = 64'h0707070707070707;
                exp_ctrl[exp_count]  = 8'hFF;
                exp_keep[exp_count]  = 8'hFF;
                exp_start[exp_count] = 1'b0;
                exp_term[exp_count]  = 1'b0;
                exp_count = exp_count + 1;
            end
            drive_idle_beat();
        end
    endtask

    // --------------------------------------------------------------------------
    // decoder output capture
    // --------------------------------------------------------------------------
    bit                    cap_en;
    int                    cap_count;
    logic [DATA_W - 1 : 0] cap_data  [0:MAX_CAP-1];
    logic [7:0]            cap_ctrl  [0:MAX_CAP-1];
    logic [7:0]            cap_keep  [0:MAX_CAP-1];
    bit                    cap_start [0:MAX_CAP-1];
    bit                    cap_term  [0:MAX_CAP-1];
    bit                    cap_err   [0:MAX_CAP-1];

    // --------------------------------------------------------------------------
    // monitors (shared across tests; per-test counters are gated by t<N>_active)
    // --------------------------------------------------------------------------
    int  cycle_ctr;
    bit  t1_active;
    int  t1_slip_count;
    int  t1_error_count;
    int  t1_block_count;
    int  t1_lock_cycle;
    bit  t1_slip_after_lock;
    bit  t1_lock_dropped;
    bit  t1_x_seen;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            cycle_ctr <= 0;
        end else begin
            cycle_ctr <= cycle_ctr + 1;

            if (t1_active) begin
                if ($isunknown(serdes_data)) t1_x_seen <= 1'b1;
                if (gearbox_valid) begin
                    t1_block_count <= t1_block_count + 1;
                    if (sync_slip)  t1_slip_count  <= t1_slip_count + 1;
                end
                // o_error during acquisition is expected: the descrambler is not
                // gated by lock, so misaligned blocks reach the decoder.
                if (o_valid && o_error) t1_error_count <= t1_error_count + 1;

                if (t1_lock_cycle >= 0) begin
                    if (sync_slip)  t1_slip_after_lock <= 1'b1;
                    if (!sync_lock) t1_lock_dropped    <= 1'b1;
                end
            end

            // cap_count is only ever cleared while cap_en is low, so there is no
            // blocking/non-blocking race on it.
            if (cap_en && o_valid && cap_count < MAX_CAP) begin
                cap_data[cap_count]  <= o_data;
                cap_ctrl[cap_count]  <= o_ctrl;
                cap_keep[cap_count]  <= o_keep;
                cap_start[cap_count] <= o_start;
                cap_term[cap_count]  <= o_terminate;
                cap_err[cap_count]   <= o_error;
                cap_count            <= cap_count + 1;
            end
        end
    end

    // compare one captured beat against one expected beat
    function automatic bit cap_matches_beat(input int ci, input int bi);
        return (cap_data[ci]  === beat_data[bi])  &&
               (cap_ctrl[ci]  === beat_ctrl[bi])  &&
               (cap_keep[ci]  === beat_keep[bi])  &&
               (cap_start[ci] === beat_start[bi]) &&
               (cap_term[ci]  === beat_term[bi])  &&
               (cap_err[ci]   === 1'b0);
    endfunction

    function automatic bit cap_matches_exp(input int ci, input int ei);
        return (cap_data[ci]  === exp_data[ei])  &&
               (cap_ctrl[ci]  === exp_ctrl[ei])  &&
               (cap_keep[ci]  === exp_keep[ei])  &&
               (cap_start[ci] === exp_start[ei]) &&
               (cap_term[ci]  === exp_term[ei])  &&
               (cap_err[ci]   === 1'b0);
    endfunction

    task automatic show_mismatch(input int ci, input string what);
        begin
            $display("        captured[%0d]: data=%h ctrl=%h keep=%h start=%b term=%b err=%b",
                     ci, cap_data[ci], cap_ctrl[ci], cap_keep[ci],
                     cap_start[ci], cap_term[ci], cap_err[ci]);
            $display("        expected %s", what);
        end
    endtask

    // shared helper: wait for block_sync to declare lock, or give up after `timeout`
    // cycles. the caller checks sync_lock afterwards.
    task automatic wait_for_lock(input int timeout);
        begin
            for (int i = 0; i < timeout; i++) begin
                @(posedge clk);
                if (sync_lock) break;
            end
        end
    endtask

    // acquire lock while streaming idle beats through the encoder (tests 3/5/6)
    task automatic acquire_lock_with_idles(input int max_beats_to_try);
        begin
            for (int i = 0; i < max_beats_to_try; i++) begin
                if (sync_lock) break;
                drive_idle_beat();
            end
        end
    endtask

    // test 1: alignment acquisition
    //   generate a stream of idle blocks (scrambled or not), pack into 64-bit words.
    //   feed into serdes_data with serdes_valid = 1.
    //   monitor sync_lock; it should assert within 66*64 cycles worst case.
    //   *: watch o_error during acquisition, it will fire on misaligned blocks.
    //      that's expected and not a bug.
    task automatic test1_alignment_acquisition();
        int timeout;
        begin
            $display("\nTEST 1: alignment acquisition");

            t1_slip_count      = 0;
            t1_error_count     = 0;
            t1_block_count     = 0;
            t1_lock_cycle      = -1;
            t1_slip_after_lock = 1'b0;
            t1_lock_dropped    = 1'b0;
            t1_x_seen          = 1'b0;

            // stream of idle blocks, scrambled and packed by the tx generator
            tx_block = rx_idle_block();

            do_reset();

            t1_active    = 1'b1;
            serdes_valid = 1'b1;

            // worst case: 66 candidate offsets x 64 headers to confirm each
            timeout = 66 * 64;
            for (int i = 0; i < timeout; i++) begin
                @(posedge clk);
                if (sync_lock) break;
            end

            if (!sync_lock) begin
                $display("  FAIL: sync_lock never asserted within %0d cycles (%0d blocks, %0d slips)",
                         timeout, t1_block_count, t1_slip_count);
                fail_count++;
                t1_active    = 1'b0;
                serdes_valid = 1'b0;
                return;
            end

            t1_lock_cycle = cycle_ctr;
            $display("  INFO: sync_lock asserted at cycle %0d (%0d blocks seen, %0d slips issued)",
                     t1_lock_cycle, t1_block_count, t1_slip_count);
            $display("  INFO: %0d decoder errors during acquisition (expected, misaligned blocks)",
                     t1_error_count);

            // lock must be real, not a transient: no slips, no drops for 300 cycles
            repeat (300) @(posedge clk);

            if (t1_x_seen) begin
                $display("  FAIL: serdes_data went X/Z during acquisition");
                fail_count++;
            end else if (t1_lock_dropped) begin
                $display("  FAIL: sync_lock dropped after acquisition");
                fail_count++;
            end else if (t1_slip_after_lock) begin
                $display("  FAIL: o_slip asserted after lock was declared");
                fail_count++;
            end else if (!sync_lock) begin
                $display("  FAIL: sync_lock not high at end of test");
                fail_count++;
            end else begin
                $display("  PASS: Test 1 (locked in %0d cycles, stable for 300 cycles)", t1_lock_cycle);
                pass_count++;
            end

            t1_active    = 1'b0;
            serdes_valid = 1'b0;
        end
    endtask

    // test 2: idle decoding after lock
    //   once locked, verify decoder produces o_idle = 1 with correct data.
    //   if using unscrambled input, there will be ~1 block of garbage after lock
    //   while the descrambler converges. after that, idle beats should be clean.
    //
    // self-contained: test 1 leaves serdes_valid low, which drops lock, so this
    // resets and re-acquires rather than assuming any prior state.
    task automatic test2_idle_decoding();
        int window;
        int min_beats;
        int beats;
        int idle_beats;
        int bad_beats;
        bit reported;
        begin
            $display("\nTEST 2: idle decoding after lock");

            window     = 200;
            min_beats  = 180;   // ~194 expected: the gearbox drops 1 cycle in 33
            beats      = 0;
            idle_beats = 0;
            bad_beats  = 0;
            reported   = 1'b0;

            // same idle stream as test 1, scrambled and packed by the tx generator
            tx_block = rx_idle_block();

            do_reset();
            serdes_valid = 1'b1;

            wait_for_lock(66 * 64);

            if (!sync_lock) begin
                $display("  FAIL: never locked, cannot check idle decoding");
                fail_count++;
                serdes_valid = 1'b0;
                return;
            end

            // let the descrambler settle after the last slip. it is self-synchronizing
            // and needs < 1 block of correctly-aligned input, and lock already implies
            // 64 clean blocks, so this is belt-and-braces.
            repeat (4) @(posedge clk);

            // an idle block is BLOCK_TYPE_CTRL (0x1e) with eight 0x00 control codes,
            // which the decoder turns into 8 x 0x07 with ctrl/keep all set.
            for (int i = 0; i < window; i++) begin
                @(posedge clk);
                if (o_valid) begin
                    beats++;
                    if (o_idle && !o_error && !o_start && !o_terminate &&
                        o_data === 64'h0707070707070707 &&
                        o_ctrl === 8'hff && o_keep === 8'hff) begin
                        idle_beats++;
                    end else begin
                        bad_beats++;
                        if (!reported) begin
                            reported = 1'b1;
                            $display("  FAIL: bad idle beat at cycle %0d:", cycle_ctr);
                            $display("        o_data=%h (expected 0707070707070707)", o_data);
                            $display("        o_ctrl=%h o_keep=%h idle=%b start=%b term=%b err=%b",
                                     o_ctrl, o_keep, o_idle, o_start, o_terminate, o_error);
                        end
                    end
                end
            end

            $display("  INFO: %0d valid beats in %0d cycles, %0d decoded as clean idle",
                     beats, window, idle_beats);

            if (bad_beats != 0) begin
                $display("  FAIL: %0d of %0d beats were not clean idle", bad_beats, beats);
                fail_count++;
            end
            // the beat-count floor matters: without it this test would pass trivially
            // if o_valid never asserted at all.
            else if (beats < min_beats) begin
                $display("  FAIL: only %0d valid beats in %0d cycles (expected >= %0d)",
                         beats, window, min_beats);
                fail_count++;
            end
            else begin
                $display("  PASS: Test 2 (%0d/%0d beats clean idle)", idle_beats, beats);
                pass_count++;
            end

            serdes_valid = 1'b0;
        end
    endtask

    // test 3: frame reception
    //   generate a frame: build XGMII beats with build_xgmii_beats(), encode them
    //   (either with the encoder module or by hand), scramble, pack into 64-bit words.
    //   feed through the RX path. verify decoder output matches the original XGMII beats.
    //   *: this is the end-to-end test. if this works, the RX path works.
    //
    // the encoder/decoder round trip preserves {data, ctrl, keep, start, terminate}
    // exactly for every beat shape, so the comparison is field-for-field. o_idle is
    // excluded: the decoder derives it from the data pattern, not from anything the
    // encoder was told.
    task automatic test3_frame_reception();
        int i;
        int first_start;
        int mism;
        begin
            $display("\nTEST 3: frame reception");

            use_encoder = 1'b1;
            inject_mask = '0;
            clear_xgmii_idle();

            make_payload(64, 1);
            rx_build_xgmii_beats();
            $display("  INFO: frame is %0d bytes -> %0d XGMII beats", payload_len, beat_count);

            do_reset();
            serdes_valid = 1'b1;

            acquire_lock_with_idles(5000);

            if (!sync_lock) begin
                $display("  FAIL: never locked, cannot send a frame");
                fail_count++;
                serdes_valid = 1'b0;
                use_encoder  = 1'b0;
                return;
            end

            // settle, then start capturing decoder output
            for (i = 0; i < 8; i++) drive_idle_beat();
            cap_en    = 1'b0;
            cap_count = 0;
            cap_en    = 1'b1;

            // idles, the frame, then idles
            for (i = 0; i < 4; i++)          drive_idle_beat();
            for (i = 0; i < beat_count; i++) drive_beat(i);
            for (i = 0; i < 20; i++)         drive_idle_beat();

            repeat (10) @(posedge clk);      // drain the pipeline
            cap_en = 1'b0;

            // anchor on the start beat, so pipeline latency doesn't matter
            first_start = -1;
            for (i = 0; i < cap_count; i++) begin
                if (cap_start[i]) begin
                    first_start = i;
                    break;
                end
            end

            if (first_start < 0) begin
                $display("  FAIL: no start beat in %0d captured beats", cap_count);
                fail_count++;
            end
            else if (first_start + beat_count > cap_count) begin
                $display("  FAIL: captured stream too short (start at %0d, %0d beats, only %0d captured)",
                         first_start, beat_count, cap_count);
                fail_count++;
            end
            else begin
                mism = 0;
                for (i = 0; i < beat_count; i++) begin
                    if (!cap_matches_beat(first_start + i, i)) begin
                        if (mism == 0) begin
                            $display("  FAIL: beat %0d of the frame does not match", i);
                            show_mismatch(first_start + i, "");
                            $display("        expected     : data=%h ctrl=%h keep=%h start=%b term=%b",
                                     beat_data[i], beat_ctrl[i], beat_keep[i],
                                     beat_start[i], beat_term[i]);
                        end
                        mism = mism + 1;
                    end
                end

                if (mism == 0) begin
                    $display("  PASS: Test 3 (%0d/%0d beats match, start at captured index %0d)",
                             beat_count, beat_count, first_start);
                    pass_count++;
                end else begin
                    $display("  FAIL: Test 3 (%0d of %0d beats mismatched)", mism, beat_count);
                    fail_count++;
                end
            end

            serdes_valid = 1'b0;
            use_encoder  = 1'b0;
        end
    endtask

    // test 4: serdes_valid drop and recovery
    //   lock, stream data, drop serdes_valid for 20 cycles, reassert.
    //   verify block_sync loses lock, then re-acquires it.
    //   verify the decoder doesn't produce valid output during the gap.
    task automatic test4_serdes_drop();
        int gap_cycles;
        int beats_in_gap;
        int errs_in_gap;
        int relock_cycle;
        bit lock_dropped;
        bit relocked;
        bit ok;
        begin
            $display("\nTEST 4: serdes_valid drop and recovery");

            gap_cycles   = 20;
            beats_in_gap = 0;
            errs_in_gap  = 0;
            relock_cycle = -1;
            lock_dropped = 1'b0;
            relocked     = 1'b0;

            tx_block = rx_idle_block();

            do_reset();
            serdes_valid = 1'b1;
            wait_for_lock(66 * 64);

            if (!sync_lock) begin
                $display("  FAIL: never locked, cannot test drop/recovery");
                fail_count++;
                serdes_valid = 1'b0;
                return;
            end

            // stream with lock held so we start from a settled state
            repeat (50) @(posedge clk);

            // ---- drop the serdes ----
            serdes_valid = 1'b0;
            for (int i = 0; i < gap_cycles; i++) begin
                @(posedge clk);
                if (!sync_lock) lock_dropped = 1'b1;
                if (o_valid) begin
                    beats_in_gap++;
                    if (o_error) errs_in_gap++;
                end
            end

            // ---- reassert and re-acquire ----
            serdes_valid = 1'b1;
            wait_for_lock(66 * 64);
            relocked = sync_lock;

            if (relocked) begin
                relock_cycle = cycle_ctr;
                // the new lock must be stable, not a one-cycle blip
                repeat (200) @(posedge clk);
                if (!sync_lock) relocked = 1'b0;
            end

            // ---- results ----
            ok = 1'b1;

            if (lock_dropped) begin
                $display("  CHECK 1 (lock drops during gap):        PASS");
            end else begin
                $display("  CHECK 1 (lock drops during gap):        FAIL - sync_lock stayed high");
                ok = 1'b0;
            end

            if (relocked) begin
                $display("  CHECK 2 (lock re-acquired, stable):     PASS (relocked at cycle %0d)",
                         relock_cycle);
            end else begin
                $display("  CHECK 2 (lock re-acquired, stable):     FAIL - no stable lock after reassert");
                ok = 1'b0;
            end

            if (beats_in_gap == 0) begin
                $display("  CHECK 3 (no decoder output during gap): PASS");
            end else begin
                $display("  CHECK 3 (no decoder output during gap): FAIL - %0d valid beats in a %0d cycle gap (%0d flagged o_error)",
                         beats_in_gap, gap_cycles, errs_in_gap);
                $display("        gearbox_rx freezes rather than clearing o_valid when i_pma_lock");
                $display("        drops (no else branch on the i_pma_lock if), and neither the");
                $display("        descrambler nor the decoder gates o_valid on sync_lock. the MAC");
                $display("        would see stale blocks presented as valid data.");
                ok = 1'b0;
            end

            if (ok) begin
                $display("  PASS: Test 4");
                pass_count++;
            end else begin
                $display("  FAIL: Test 4");
                fail_count++;
            end

            serdes_valid = 1'b0;
        end
    endtask

    // test 5: sustained traffic
    //   generate 500+ beats of mixed frames and idles.
    //   feed through the full pipeline. count start/terminate events.
    //   verify every frame that went in comes out with matching data.
    //
    // every driven beat (idles included) is logged, and the whole captured stream is
    // compared against it, anchored on the first start beat. frames are never
    // truncated, so start and terminate counts are exact.
    task automatic test5_sustained();
        int i;
        int total;
        int frames;
        int idles;
        int cap_first;
        int exp_first;
        int n_compare;
        int mism;
        int cap_starts;
        int cap_terms;
        begin
            $display("\nTEST 5: sustained traffic");

            use_encoder = 1'b1;
            inject_mask = '0;
            clear_xgmii_idle();

            total      = 0;
            frames     = 0;
            exp_count  = 0;
            mism       = 0;
            cap_starts = 0;
            cap_terms  = 0;

            do_reset();
            serdes_valid = 1'b1;

            acquire_lock_with_idles(5000);

            if (!sync_lock) begin
                $display("  FAIL: never locked, cannot run sustained traffic");
                fail_count++;
                serdes_valid = 1'b0;
                use_encoder  = 1'b0;
                return;
            end

            for (i = 0; i < 8; i++) drive_idle_beat();
            cap_en    = 1'b0;
            cap_count = 0;
            cap_en    = 1'b1;

            while (total < 500) begin
                // 1..8 idle beats
                idles = 1 + (frames % 8);
                for (i = 0; i < idles; i++) begin
                    send_and_log_idle();
                    total = total + 1;
                end

                // one whole frame, 46..128 bytes. never truncated, so the start and
                // terminate counts stay exact.
                make_payload(46 + ((frames * 17) % 83), frames + 2);
                rx_build_xgmii_beats();
                if (total + beat_count > 520) break;

                frames = frames + 1;
                for (i = 0; i < beat_count; i++) begin
                    send_and_log_beat(i);
                    total = total + 1;
                end
            end

            for (i = 0; i < 20; i++) drive_idle_beat();
            repeat (10) @(posedge clk);
            cap_en = 1'b0;

            $display("  INFO: drove %0d beats in %0d frames, captured %0d beats",
                     total, frames, cap_count);

            // anchor both streams on their first start beat
            cap_first = -1;
            for (i = 0; i < cap_count; i++) begin
                if (cap_start[i]) begin
                    cap_first = i;
                    break;
                end
            end
            exp_first = -1;
            for (i = 0; i < exp_count; i++) begin
                if (exp_start[i]) begin
                    exp_first = i;
                    break;
                end
            end

            for (i = 0; i < cap_count; i++) begin
                if (cap_start[i]) cap_starts = cap_starts + 1;
                if (cap_term[i])  cap_terms  = cap_terms  + 1;
            end
            $display("  INFO: captured %0d start and %0d terminate events (expected %0d each)",
                     cap_starts, cap_terms, frames);

            if (cap_first < 0 || exp_first < 0) begin
                $display("  FAIL: no start beat found (captured %0d, expected %0d)",
                         cap_first, exp_first);
                fail_count++;
            end
            else if (cap_starts != frames || cap_terms != frames) begin
                $display("  FAIL: start/terminate count mismatch (got %0d/%0d, expected %0d/%0d)",
                         cap_starts, cap_terms, frames, frames);
                fail_count++;
            end
            else begin
                n_compare = exp_count - exp_first;
                if (cap_first + n_compare > cap_count)
                    n_compare = cap_count - cap_first;

                for (i = 0; i < n_compare; i++) begin
                    if (!cap_matches_exp(cap_first + i, exp_first + i)) begin
                        if (mism == 0) begin
                            $display("  FAIL: stream diverges at offset %0d after the first start", i);
                            show_mismatch(cap_first + i, "");
                            $display("        expected     : data=%h ctrl=%h keep=%h start=%b term=%b",
                                     exp_data[exp_first + i], exp_ctrl[exp_first + i],
                                     exp_keep[exp_first + i], exp_start[exp_first + i],
                                     exp_term[exp_first + i]);
                        end
                        mism = mism + 1;
                    end
                end

                if (mism == 0) begin
                    $display("  PASS: Test 5 (%0d beats matched across %0d frames)", n_compare, frames);
                    pass_count++;
                end else begin
                    $display("  FAIL: Test 5 (%0d of %0d beats mismatched)", mism, n_compare);
                    fail_count++;
                end
            end

            serdes_valid = 1'b0;
            use_encoder  = 1'b0;
        end
    endtask

    // test 6: error injection
    //   corrupt a 64-bit word mid-stream (flip some bits).
    //   verify the decoder flags o_error on the affected block.
    //   verify subsequent blocks still decode correctly (self-synchronizing).
    //
    // a corrupted 64-bit word straddles two 66-bit blocks, and the descrambler's
    // x^58 + x^39 + 1 taps multiply every input bit error into three output bit
    // errors, so the damage lands in sync headers / block types / control codes and
    // the decoder should flag it. after ~1 block of clean input the descrambler has
    // flushed the bad bits and decoding recovers on its own.
    task automatic test6_error_injection();
        int i;
        int errs;
        int clean_run;
        int recovery_idx;
        bit ok;
        begin
            $display("\nTEST 6: error injection");

            use_encoder = 1'b1;
            inject_mask = '0;
            clear_xgmii_idle();

            errs         = 0;
            clean_run    = 0;
            recovery_idx = -1;

            do_reset();
            serdes_valid = 1'b1;

            acquire_lock_with_idles(5000);

            if (!sync_lock) begin
                $display("  FAIL: never locked, cannot inject errors");
                fail_count++;
                serdes_valid = 1'b0;
                use_encoder  = 1'b0;
                return;
            end

            // settle. the encoder inputs stay parked on an idle beat, so the stream
            // keeps flowing without further drive calls.
            repeat (20) @(posedge clk);

            // corrupt exactly one 64-bit word: a 16-bit burst
            inject_mask = 64'h0000_0000_0000_FFFF;
            @(posedge clk);
            inject_mask = '0;

            // watch for errors, then for sustained clean idle decoding
            for (i = 0; i < 60; i++) begin
                @(posedge clk);
                if (o_valid) begin
                    if (o_error) begin
                        errs      = errs + 1;
                        clean_run = 0;
                    end else if (o_idle && o_data === 64'h0707070707070707 &&
                                 o_ctrl === 8'hff && o_keep === 8'hff) begin
                        clean_run = clean_run + 1;
                        if (errs > 0 && clean_run >= 10 && recovery_idx < 0)
                            recovery_idx = i;
                    end else begin
                        clean_run = 0;
                    end
                end
            end

            ok = 1'b1;

            if (errs > 0) begin
                $display("  CHECK 1 (corruption flagged):     PASS (%0d blocks flagged o_error)", errs);
            end else begin
                $display("  CHECK 1 (corruption flagged):     FAIL - no o_error after injection");
                $display("        the flipped bits may have descrambled into a still-legal block;");
                $display("        try a different inject_mask.");
                ok = 1'b0;
            end

            if (recovery_idx >= 0) begin
                $display("  CHECK 2 (self-synchronizing):     PASS (10 clean idle beats by cycle %0d after injection)",
                         recovery_idx);
            end else begin
                $display("  CHECK 2 (self-synchronizing):     FAIL - never saw 10 consecutive clean idle beats");
                ok = 1'b0;
            end

            // a couple of bad headers is nowhere near block_sync's 65-in-1024 threshold
            if (sync_lock) begin
                $display("  CHECK 3 (lock retained):          PASS");
            end else begin
                $display("  CHECK 3 (lock retained):          FAIL - lock dropped on a single bad word");
                ok = 1'b0;
            end

            if (ok) begin
                $display("  PASS: Test 6");
                pass_count++;
            end else begin
                $display("  FAIL: Test 6");
                fail_count++;
            end

            serdes_valid = 1'b0;
            use_encoder  = 1'b0;
        end
    endtask

    initial begin
        $display("==============================================");
        $display("  RX path integration testbench");
        $display("==============================================");
        pass_count  = 0;
        fail_count  = 0;
        t1_active   = 1'b0;
        use_encoder = 1'b0;
        inject_mask = '0;
        cap_en      = 1'b0;
        cap_count   = 0;
        exp_count   = 0;
        tx_block    = rx_idle_block();
        clear_xgmii_idle();

        do_reset();

        test1_alignment_acquisition();
        test2_idle_decoding();
        test3_frame_reception();
        test4_serdes_drop();
        test5_sustained();
        test6_error_injection();

        $display("\n==============================================");
        $display("  Results: %0d PASSED, %0d FAILED", pass_count, fail_count);
        $display("==============================================");
        $finish;
    end

endmodule
