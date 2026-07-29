`timescale 1ns/1ps
`default_nettype none
`include "eth_frame_pkg.sv"
`include "gearbox_tx.sv"
`include "scrambler.sv"
`include "encoder.sv"

module tx_path_tb;
    import eth_frame_pkg::*;

    localparam DATAW = 64;
    localparam HEADW = 2;

    logic clk;
    logic rstn;

    logic              ivalid;
    logic [63:0]       idata;
    logic [7:0]        ictrl;
    logic [7:0]        ikeep;
    logic              istart;
    logic              iidle;
    logic              iterminate;
    logic              ierror;

    logic [63:0]       serdesdata;
    logic              accept;

    logic [65:0]       encdata;
    logic              encvalid;
    logic [65:0]       scramdata;
    logic              scramvalid;

    int pass_count, fail_count;

    int   cycle_ctr;
    int   accept_low_ctr;
    int   last_accept_low_cycle;
    logic accept_d;

    logic test1_active;
    logic test1_backpressure_fail;

    xgmii_beat_t beat;
    xgmii_beat_t idle;

    payload_t    p;
    xgmii_beat_t frame_beats [0:255];
    int          nbeats;
    int          t2_accept_low_ctr;
    logic        t2_active;

    payload_t    p1;
    payload_t    p2;
    xgmii_beat_t frame_beats1 [0:255];
    xgmii_beat_t frame_beats2 [0:255];
    int          nbeats1;
    int          nbeats2;
    int          t3_accept_low_ctr;
    logic        t3_active;

    payload_t    p4;
    xgmii_beat_t frame_beats4 [0:255];
    int          nbeats4;
    xgmii_beat_t t4_curr_beat;
    xgmii_beat_t t4_saved_beat;
    xgmii_beat_t t4_resume_beat;
    int          t4_accept_low_ctr;
    logic        t4_active;
    logic        t4_saved_valid;
    logic        t4_resume_valid;
    logic        t4_stall_seen;

    logic        t5_active;
    int          t5_serdes_word_count;
    int          t5_total_beats_sent;
    int          t5_frame_count;
    logic [63:0] t5_serdes_log [0:4095];
    payload_t    p5;
    xgmii_beat_t frame_beats5 [0:255];
    int          nbeats5;

    logic        t6_active;
    int          t6_total_beats_sent;
    int          t6_phase;
    int          t6_serdes_word_count;
    logic [63:0] t6_serdes_log [0:1023];
    payload_t    p6;
    xgmii_beat_t frame_beats6 [0:255];
    int          nbeats6;

    encoder #(.DATAW(DATAW)) u_encoder (
        .clk        (clk),
        .rstn       (rstn),
        .ivalid     (ivalid),
        .idata      (idata),
        .ictrl      (ictrl),
        .ikeep      (ikeep),
        .istart     (istart),
        .iidle      (iidle),
        .iterminate (iterminate),
        .ierror     (ierror),
        .ovalid     (encvalid),
        .odata      (encdata)
    );

    scrambler #(.DATAW(DATAW)) u_scrambler (
        .clk       (clk),
        .rstn      (rstn),
        .ivalid    (encvalid),
        .iencdata  (encdata),
        .ovalid    (scramvalid),
        .oscramdata(scramdata)
    );

    gearboxtx #(.DATAW(DATAW), .HEADW(HEADW)) u_gearboxtx (
        .clk    (clk),
        .rstn   (rstn),
        .ihead  (scramdata[1:0]),
        .idata  (scramdata[65:2]),
        .odata  (serdesdata),
        .oaccept(accept)
    );

    initial clk = 0;
    always #3.2 clk = ~clk;

    task automatic clear_mac_inputs;
        begin
            ivalid     = 0;
            idata      = '0;
            ictrl      = '0;
            ikeep      = '0;
            istart     = 0;
            iidle      = 0;
            iterminate = 0;
            ierror     = 0;
        end
    endtask

    task automatic doreset;
        begin
            rstn = 0;
            clear_mac_inputs();
            repeat (2) @(posedge clk);
            rstn = 1;
        end
    endtask

    task automatic drivebeatbp(input xgmii_beat_t b);
        begin
            while (!accept) @(posedge clk);
            ivalid     = 1;
            idata      = b.data;
            ictrl      = b.ctrl;
            ikeep      = b.keep;
            istart     = b.start;
            iidle      = b.idle;
            iterminate = b.terminate;
            ierror     = 0;
            @(posedge clk);
        end
    endtask


// --------------------------------------------------------------------------
    // this tb answers the question: does data survive the entire TX pipeline?
    //
    // you can't directly check the SerDes output against XGMII input because
    // it's been encoded, scrambled, and repacked. but you CAN:
    //
    //   1. verify the output bitstream is continuous (no gaps, no X's)
    //   2. verify backpressure propagation (frames stall cleanly when accept drops)
    //   3. feed the output into an RX path (or the rx_path_tb) for full loopback
    //   4. collect the raw output bits and reconstruct blocks manually to verify
    //      encoding and scrambling
    //
    // *: the gearbox has a 1-cycle output latency. the scrambler and encoder are
    //    combinational. total path latency from XGMII input to SerDes output = 1 cycle.
    // --------------------------------------------------------------------------

    // test 1: idle stream
    //   feed 100 idle beats. verify serdes_data has no X's or Z's.
    //   verify backpressure timing (accept drops every 33 cycles).

    // test 2: single frame
    //   generate a frame with build_xgmii_beats. drive it through.
    //   verify no errors, verify accept behavior during the frame.

    // test 3: back-to-back frames with idles
    //   frame, 3 idles, frame, 10 idles, frame.
    //   verify accept drops are handled cleanly between frames.

    // test 4: frame spanning a backpressure event
    //   time a frame so that a data beat coincides with accept going low.
    //   verify the pipeline stalls and resumes correctly.
    //   *: this is the critical test. if the MAC side doesn't hold its inputs
    //      when accept drops, a beat gets lost or duplicated.

    // test 5: sustained load
    //   500+ beats of mixed frames and idles.
    //   collect all serdes_data output words. verify no X/Z values.

    // test 6: mid-stream reset
    //   feed 50 beats, reset, feed 50 more.
    //   verify clean recovery;


    always @(posedge clk) begin
        if (!rstn) begin // reset all these parameters 
            cycle_ctr               <= 0;
            accept_low_ctr          <= 0;
            last_accept_low_cycle   <= -1;
            accept_d                <= 1'b1; // assume previous cycle was accept high
            test1_backpressure_fail <= 1'b0;

            t2_accept_low_ctr       <= 0;
            t3_accept_low_ctr       <= 0;

            t4_accept_low_ctr       <= 0;
            t4_saved_valid          <= 1'b0;
            t4_resume_valid         <= 1'b0;
            t4_stall_seen           <= 1'b0;

            t5_serdes_word_count    <= 0;
            t6_serdes_word_count    <= 0;
        end
        else begin
            cycle_ctr <= cycle_ctr + 1;

            // global X/Z monitor while any active test is running
            if ((test1_active || t2_active || t3_active || t4_active || t5_active || t6_active) &&
                $isunknown(serdes_data)) begin
                $display("[%0t] FAIL: serdes_data has X/Z = %h", $time, serdes_data);
                fail_count <= fail_count + 1;
            end

            // falling edge of accept
            if (accept_d && !accept) begin
                if (test1_active) begin
                    accept_low_ctr <= accept_low_ctr + 1;
                    $display("[%0t] INFO: accept low at cycle %0d", $time, cycle_ctr);

                    if (last_accept_low_cycle >= 0) begin
                        if ((cycle_ctr - last_accept_low_cycle) != 33) begin
                            $display("[%0t] FAIL: accept spacing = %0d cycles, expected 33",
                                     $time, cycle_ctr - last_accept_low_cycle);
                            test1_backpressure_fail <= 1'b1;
                            fail_count <= fail_count + 1;
                        end
                    end

                    last_accept_low_cycle <= cycle_ctr;
                end

                if (t2_active) begin
                    t2_accept_low_ctr <= t2_accept_low_ctr + 1;
                    $display("[%0t] INFO: accept dropped during Test 2", $time);
                end

                if (t3_active) begin
                    t3_accept_low_ctr <= t3_accept_low_ctr + 1;
                    $display("[%0t] INFO: accept dropped during Test 3", $time);
                end

                if (t4_active) begin
                    t4_accept_low_ctr <= t4_accept_low_ctr + 1;
                    t4_saved_beat     <= t4_curr_beat;
                    t4_saved_valid    <= 1'b1;
                    t4_stall_seen     <= 1'b1;
                    $display("[%0t] INFO: accept dropped during Test 4", $time);
                end
            end

            // rising edge of accept: used for Test 4 resume snapshot
            if (t4_active && !accept_d && accept && t4_stall_seen && !t4_resume_valid) begin
                t4_resume_beat  <= t4_curr_beat;
                t4_resume_valid <= 1'b1;
                $display("[%0t] INFO: accept resumed during Test 4", $time);
            end

            // capture serdes output logs for Test 5
            if (t5_active && !$isunknown(serdes_data)) begin
                if (t5_serdes_word_count < 4096) begin
                    t5_serdes_log[t5_serdes_word_count] <= serdes_data;
                    t5_serdes_word_count <= t5_serdes_word_count + 1;
                end
            end

            // capture serdes output logs for Test 6
            if (t6_active && !$isunknown(serdes_data)) begin
                if (t6_serdes_word_count < 1024) begin
                    t6_serdes_log[t6_serdes_word_count] <= serdes_data;
                    t6_serdes_word_count <= t6_serdes_word_count + 1;
                end
            end

            accept_d <= accept;
        end
    end


    initial begin
        pass_count = 0;
        fail_count = 0;

        test1_active = 0; t2_active = 0; t3_active = 0;
        t4_active = 0; t5_active = 0; t6_active = 0;

        doreset();

        // TEST 1
        $display("TEST 1: idle stream");
        cycle_ctr = 0;
        accept_low_ctr = 0;
        last_accept_low_cycle = -1;
        acceptd = accept;
        test1backpressurefail = 0;
        test1_active = 1;
        for (int i = 0; i < 100; i++) begin // feed 100 idle
            beat = idle_beat();
            drivebeatbp(beat);
        end
        clear_mac_inputs(); // reset parameters
        repeat (5) @(posedge clk);
        test1_active = 0;

        if (accept_low_ctr == 0) begin
            $display("FAIL: accept never went low during idle stream");
            fail_count = fail_count +1;
        end else if (!test1backpressurefail) begin // testing done in monitor
            $display("PASS: Test 1");
            pass_count = pass_count +1;
        end

        // TEST 2
        $display("TEST 2: single frame");
        t2acceptlowctr = 0;
        t2_active = 1;
        p = gen_random_payload(64);
        nbeats = build_xgmii_beats(p, frame_beats); // generating frame with build_xgmii function
        
        if (nbeats <= 0) begin
            $display("FAIL: build_xgmii_beats returned %0d beats", nbeats);
            fail_count = fail_count +1;
        end else begin
            for (int i = 0; i < nbeats; i++) begin // drive frame through
                drivebeatbp(frame_beats[i]);
                end
            pass_count = pass_count +1;
        end

        clear_mac_inputs();
        repeat (5) @(posedge clk);
        t2_active = 0;

        // TEST 3
        $display("TEST 3: back-to-back frames with idles");
        t3_active = 1;
        p1 = gen_random_payload(64); // frame 1
        p2 = gen_random_payload(64); // frame 2
        
        nbeats1 = build_xgmii_beats(p1, frame_beats1);
        nbeats2 = build_xgmii_beats(p2, frame_beats2);

        if (nbeats1 <= 0 || nbeats2 <= 0) begin
            $display("FAIL: build_xgmii_beats failed in Test 3");
            fail_count = fail_count +1;
        end else begin
            for (int i = 0; i < nbeats1; i++) begin // drive first frame
                drivebeatbp(frame_beats1[i]);
            end
            for (int i = 0; i < 3; i++) begin  // 3 idle beats
                beat = idle_beat();
                drivebeatbp(beat);
            end
            for (int i = 0; i < nbeats2; i++) begin // drive 2nd frame
                drivebeatbp(frame_beats2[i]); 
            end
            for (int i = 0; i < 10; i++) begin // 10 idles
                beat = idle_beat(); drivebeatbp(beat);
            end
            for (int i = 0; i < nbeats1; i++) begin  // drive first frame again
                drivebeatbp(frame_beats1[i]);
            end
        end

        clear_mac_inputs();
        repeat (5) @(posedge clk);
        t3_active = 0;

        // TEST 4
        $display("TEST 4: frame spanning backpressure event");

        t4_active         = 1'b1;
        t4_accept_low_ctr = 0;
        t4_saved_valid    = 1'b0;
        t4_resume_valid   = 1'b0;
        t4_stall_seen     = 1'b0;

        p4 = gen_random_payload(64);
        nbeats4 = build_xgmii_beats(p4, frame_beats4);

        for (int i = 0; i < 30; i++) begin // drive first 30 idle to get closer to a drop
            beat = idle_beat();
            drive_beat_bp(beat);
        end

        for (int i = 0; i < nbeats4; i++) begin // begin driving the actual frame
            t4_curr_beat = frame_beats4[i]; // continually update the current_beat (saved for comparison before/after drop)

            i_valid     = 1'b1;
            i_data      = t4_curr_beat.data;
            i_ctrl      = t4_curr_beat.ctrl;
            i_keep      = t4_curr_beat.keep;
            i_start     = t4_curr_beat.start;
            i_idle      = t4_curr_beat.idle;
            i_terminate = t4_curr_beat.terminate;
            i_error     = 1'b0;

            // keep it stable until the DUT says it can accept
            while (1) begin
                @(posedge clk);
                if (!accept) begin
                    t4_stall_seen     = 1'b1;
                    t4_saved_beat     = t4_curr_beat;
                    t4_saved_valid    = 1'b1;
                    t4_accept_low_ctr = t4_accept_low_ctr + 1;
                end else if (t4_stall_seen) begin
                    t4_resume_beat  = t4_curr_beat;
                    t4_resume_valid = 1'b1;
                    break;
                end
            end
        end

        i_valid     = 1'b0;
        i_data      = '0;
        i_ctrl      = '0;
        i_keep      = '0;
        i_start     = 1'b0;
        i_idle      = 1'b0;
        i_terminate = 1'b0;
        i_error     = 1'b0;

        // TEST 5
        $display("TEST 5: sustained load");
        t5_active = 1;
        t5serdeswordcount = 0;
        t5totalbeatssent = 0;
        t5framecount = 0;

        while (t5totalbeatssent < 500) begin // send 500 beats
            if ($urandom_range(0,3) == 0) begin // random outcome: idle or frame
                int idlecount;
                idlecount = $urandom_range(1,8); // random idle beats 1-8
                for (int i = 0; i < idlecount && t5totalbeatssent < 500; i++) begin
                    beat = idle_beat();
                    drivebeatbp(beat);
                    t5totalbeatssent++;
                end
            end else begin // frames sent
                int len;
                len = $urandom_range(46,128); // random length of frame
                p5 = gen_random_payload(len);
                nbeats5 = build_xgmii_beats(p5, frame_beats5);
                if (nbeats5 > 0) begin
                    t5framecount++;
                    for (int i = 0; i < nbeats5 && t5totalbeatssent < 500; i++) begin
                        drivebeatbp(frame_beats5[i]);
                        t5totalbeatssent++;
                    end
                end
            end
        end
        for (int i = 0; i < t5_serdes_word_count; i++) begin
            $display("t5_serdes[%0d] = %h", i, t5_serdes_log[i]); // output serdes data
        end
        clear_mac_inputs();
        repeat (5) @(posedge clk);
        t5_active = 0;
        pass_count = pass_count +1;

        // TEST 6
        // 1 - internal state return to reset state 
        // 2 - after reset, accept new traffic and produce no X/Z
    
        // TEST 6: mid-stream reset
        $display("TEST 6: mid-stream reset");
        t6_active = 1'b1;

        logic [63:0] t6_log_pre  [0:1023]; // will compare before/after to ensure accuracy
        logic [63:0] t6_log_post [0:1023];
        int t6_words_pre, t6_words_post;

        xgmii_beat_t t6_beats [0:63];
        int t6_nbeats;

        payload_t t6_payload; // reference payload
        for (int i = 0; i < 80; i++) begin
            t6_payload.bytes[i] = i[7:0];
        end
        t6_payload.len = 80;
        t6_nbeats = build_xgmii_beats(t6_payload, t6_beats);

        t6_serdes_word_count = 0;
        t6_total_beats_sent  = 0;

        while (t6_total_beats_sent < 50) begin // send 50 beats
            if (t6_total_beats_sent < 5) begin
                beat = idle_beat();
                drive_beat_bp(beat);
            end
            else begin // next 45 beats from reference pattern from t6_beats
                int idx;
                idx = (t6_total_beats_sent - 5) % t6_nbeats; // wraps t6 beats if index exceded
                drive_beat_bp(t6_beats[idx]);
            end
            t6_total_beats_sent = t6_total_beats_sent + 1;
        end

        repeat (5) @(posedge clk);

        t6_words_pre = t6_serdes_word_count;
        for (int i = 0; i < t6_words_pre; i++) begin
            t6_log_pre[i] = t6_serdes_log[i]; // record BEFORE the reset
        end

        $display("INFO: asserting reset after first 50 beats");
        do_reset(); // reset now

        t6_serdes_word_count = 0; // send next batch of 50 bits
        t6_total_beats_sent  = 0;

        while (t6_total_beats_sent < 50) begin
            if (t6_total_beats_sent < 5) begin
                beat = idle_beat();
                drive_beat_bp(beat);
            end
            else begin
                int idx;
                idx = (t6_total_beats_sent - 5) % t6_nbeats;
                drive_beat_bp(t6_beats[idx]);
            end
            t6_total_beats_sent = t6_total_beats_sent + 1;
        end

        repeat (5) @(posedge clk);

        t6_words_post = t6_serdes_word_count; // record AFTER reset
        for (int i = 0; i < t6_words_post; i++) begin
            t6_log_post[i] = t6_serdes_log[i];
        end


        if (t6_words_pre != t6_words_post) begin // compare before - after
            $display("FAIL: Test 6 word-count mismatch pre=%0d post=%0d",
                    t6_words_pre, t6_words_post);
            fail_count = fail_count + 1;
        end
        else begin
            bit mismatch;
            mismatch = 0;

            for (int i = 0; i < t6_words_pre; i++) begin
                if (t6_log_pre[i] !== t6_log_post[i]) begin
                    $display("FAIL: Test 6 mismatch at word %0d pre=%h post=%h", i, t6_log_pre[i], t6_log_post[i]);
                    mismatch = 1;
                    fail_count = fail_count + 1;
                    break;
                end
            end

            if (!mismatch) begin
                $display("PASS: Test 6 clean recovery verified");
                pass_count = pass_count + 1;
            end
        end

        t6_active = 1'b0;

        $display("Results: %0d PASSED, %0d FAILED", passcount, fail_count);
        $finish;
    end
endmodule