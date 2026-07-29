`timescale 1ns / 1ps

// tb for ip_metadata_assembler - drives capture_done/header_incomplete/
// checksum_valid pulses directly (as if a capture module and checksum
// module were feeding it) and checks the packed metadata word, timing,
// and the order-independence / same-cycle edge cases the module exists
// to handle.

module tb_ip_metadata_assembler;

    logic clk, rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    logic         tvalid, tready, tlast;
    logic [31:0]  src_ip, dst_ip;
    logic [15:0]  total_len;
    logic [7:0]   protocol, ttl;
    logic [5:0]   dscp;
    logic [1:0]   ecn;
    logic [3:0]   ihl;
    logic         capture_done, header_incomplete;
    logic         checksum_ok, checksum_valid;

    logic [109:0] metadata;
    logic         metadata_valid;
    logic         assembly_incomplete;

    ip_metadata_assembler dut (
        .clk(clk), .rst_n(rst_n),
        .tvalid(tvalid), .tready(tready), .tlast(tlast),
        .src_ip(src_ip), .dst_ip(dst_ip), .total_len(total_len),
        .protocol(protocol), .ttl(ttl), .dscp(dscp), .ecn(ecn), .ihl(ihl),
        .capture_done(capture_done), .header_incomplete(header_incomplete),
        .checksum_ok(checksum_ok), .checksum_valid(checksum_valid),
        .metadata(metadata), .metadata_valid(metadata_valid),
        .assembly_incomplete(assembly_incomplete)
    );

    // packet A fields, picked so every field is distinguishable in the packed word
    localparam [31:0] A_SRC   = 32'hAABB_CCDD;
    localparam [31:0] A_DST   = 32'h1122_3344;
    localparam [15:0] A_TLEN  = 16'd100;
    localparam [7:0]  A_PROTO = 8'd6;
    localparam [7:0]  A_TTL   = 8'd50;
    localparam [5:0]  A_DSCP  = 6'h1F;
    localparam [1:0]  A_ECN   = 2'h2;
    localparam [3:0]  A_IHL   = 4'h5;

    // packet B fields, distinct from A, for the back-to-back check
    localparam [31:0] B_SRC   = 32'h0A00_0001;
    localparam [31:0] B_DST   = 32'h0A00_0002;
    localparam [15:0] B_TLEN  = 16'd40;
    localparam [7:0]  B_PROTO = 8'd17;
    localparam [7:0]  B_TTL   = 8'd128;
    localparam [5:0]  B_DSCP  = 6'h00;
    localparam [1:0]  B_ECN   = 2'h0;
    localparam [3:0]  B_IHL   = 4'h5;

    int errors = 0;

    task automatic check(logic cond, string msg);
        if (cond) $display("[TB] PASS: %s", msg);
        else begin
            $error("[TB] FAIL: %s", msg);
            errors++;
        end
    endtask

    task automatic check_metadata(input [31:0] exp_src, exp_dst, input [15:0] exp_tlen,
                                   input [7:0] exp_proto, exp_ttl, input [5:0] exp_dscp,
                                   input [1:0] exp_ecn, input [3:0] exp_ihl,
                                   input exp_cksum_ok, input exp_valid_bit, string tag);
        check(metadata[109:78] == exp_src,   {tag, ": src_ip"});
        check(metadata[77:46]  == exp_dst,   {tag, ": dst_ip"});
        check(metadata[45:30]  == exp_tlen,  {tag, ": total_len"});
        check(metadata[29:22]  == exp_proto, {tag, ": protocol"});
        check(metadata[21:14]  == exp_ttl,   {tag, ": ttl"});
        check(metadata[13:8]   == exp_dscp,  {tag, ": dscp"});
        check(metadata[7:6]    == exp_ecn,   {tag, ": ecn"});
        check(metadata[5:2]    == exp_ihl,   {tag, ": ihl"});
        check(metadata[1]      == exp_cksum_ok, {tag, ": checksum_ok bit"});
        check(metadata[0]      == exp_valid_bit, {tag, ": valid bit"});
    endtask

    task automatic drive_fields(input [31:0] s, d, input [15:0] tl,
                                 input [7:0] p, t, input [5:0] ds, input [1:0] ec, input [3:0] ih);
        src_ip = s; dst_ip = d; total_len = tl; protocol = p; ttl = t;
        dscp = ds; ecn = ec; ihl = ih;
    endtask

    // waits up to max_cycles for metadata_valid to pulse, holding all pulse
    // inputs low while waiting. deliberately doesn't assume a fixed latency -
    // that's an implementation detail we shouldn't hardcode into the tb.
    task automatic wait_for_metadata(output logic got_it, input int max_cycles);
        int i;
        got_it = 1'b0;
        capture_done = 1'b0; header_incomplete = 1'b0; checksum_valid = 1'b0; tlast = 1'b0;
        for (i = 0; i < max_cycles; i++) begin
            @(posedge clk);
            if (metadata_valid) begin
                got_it = 1'b1;
                i = max_cycles; // break
            end
        end
    endtask

    task automatic reset_env();
        rst_n = 1'b0;
        tvalid = 1'b1; tready = 1'b1; tlast = 1'b0;
        capture_done = 1'b0; header_incomplete = 1'b0;
        checksum_valid = 1'b0; checksum_ok = 1'b0;
        drive_fields('0, '0, '0, '0, '0, '0, '0, '0);
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    endtask

    logic got_it;

    initial begin
        reset_env();

        
        $display("\n[TB] === SCENARIO 1: normal order (fields then checksum) ===");
        drive_fields(A_SRC, A_DST, A_TLEN, A_PROTO, A_TTL, A_DSCP, A_ECN, A_IHL);
        capture_done = 1'b1;
        @(posedge clk);
        capture_done = 1'b0;
        @(posedge clk); // capture_done_d fires here, have_fields becomes true after this edge
        checksum_valid = 1'b1; checksum_ok = 1'b1;
        @(posedge clk);
        checksum_valid = 1'b0;
        tlast = 1'b1;
        @(posedge clk);
        tlast = 1'b0;
        check(metadata_valid == 1'b1, "S1: metadata_valid pulses the cycle after tlast when both sources already latched");
        check_metadata(A_SRC, A_DST, A_TLEN, A_PROTO, A_TTL, A_DSCP, A_ECN, A_IHL, 1'b1, 1'b1, "S1");
        check(assembly_incomplete == 1'b0, "S1: assembly_incomplete stays low for a well-formed packet");
        @(posedge clk);
        check(metadata_valid == 1'b0, "S1: metadata_valid is a single-cycle pulse");

        
        $display("\n[TB] === SCENARIO 2: reverse order (checksum then fields) ===");
        drive_fields(B_SRC, B_DST, B_TLEN, B_PROTO, B_TTL, B_DSCP, B_ECN, B_IHL);
        checksum_valid = 1'b1; checksum_ok = 1'b1;
        @(posedge clk);
        checksum_valid = 1'b0;
        capture_done = 1'b1;
        @(posedge clk);
        capture_done = 1'b0;
        @(posedge clk); // capture_done_d fires, have_fields true after this edge
        tlast = 1'b1;
        @(posedge clk);
        tlast = 1'b0;
        check(metadata_valid == 1'b1, "S2: metadata_valid pulses even though checksum arrived first");
        check_metadata(B_SRC, B_DST, B_TLEN, B_PROTO, B_TTL, B_DSCP, B_ECN, B_IHL, 1'b1, 1'b1, "S2");

        
        $display("\n[TB] === SCENARIO 3: capture_done and tlast on the same cycle ===");
        drive_fields(A_SRC, A_DST, A_TLEN, A_PROTO, A_TTL, A_DSCP, A_ECN, A_IHL);
        checksum_valid = 1'b1; checksum_ok = 1'b1;
        @(posedge clk);
        checksum_valid = 1'b0;
        capture_done = 1'b1;
        tlast = 1'b1;           // both asserted the same cycle
        @(posedge clk);
        capture_done = 1'b0;
        tlast = 1'b0;
        check(metadata_valid == 1'b0, "S3: metadata_valid does NOT fire the same cycle tlast lands (dst_ip not ready yet)");
        wait_for_metadata(got_it, 5);
        check(got_it, "S3: metadata_valid eventually pulses once dst_ip catches up (tlast_pending path)");
        check_metadata(A_SRC, A_DST, A_TLEN, A_PROTO, A_TTL, A_DSCP, A_ECN, A_IHL, 1'b1, 1'b1, "S3");

       
        $display("\n[TB] === SCENARIO 4: header_incomplete forces an immediate drop ===");
        header_incomplete = 1'b1;
        @(posedge clk);
        header_incomplete = 1'b0;
        check(metadata_valid == 1'b1, "S4: metadata_valid pulses immediately on header_incomplete");
        check(assembly_incomplete == 1'b1, "S4: assembly_incomplete asserted for a runt packet");
        check(metadata[0] == 1'b0, "S4: valid bit is 0 for a force-closed word");

        
        $display("\n[TB] === SCENARIO 5: checksum arrives the same cycle as tlast ===");
        drive_fields(B_SRC, B_DST, B_TLEN, B_PROTO, B_TTL, B_DSCP, B_ECN, B_IHL);
        capture_done = 1'b1;
        @(posedge clk);
        capture_done = 1'b0;
        @(posedge clk); // have_fields true after this edge
        checksum_valid = 1'b1; checksum_ok = 1'b1;
        tlast = 1'b1;            // same cycle as checksum_valid
        @(posedge clk);
        checksum_valid = 1'b0;
        tlast = 1'b0;
        check(metadata_valid == 1'b0, "S5: does NOT emit the same cycle checksum first arrives (have_checksum not set yet at this edge)");
        wait_for_metadata(got_it, 5);
        check(got_it, "S5: eventually emits via the tlast_pending fallback, one cycle later");
        check(metadata[1] == 1'b1, "S5: checksum_ok bit correct once it does emit");
        check(metadata[0] == 1'b1, "S5: valid bit set - this was a well-formed packet");

        
        $display("\n[TB] === SCENARIO 6: back-to-back packets, no leakage ===");
        drive_fields(A_SRC, A_DST, A_TLEN, A_PROTO, A_TTL, A_DSCP, A_ECN, A_IHL);
        capture_done = 1'b1;
        @(posedge clk);
        capture_done = 1'b0;
        @(posedge clk);
        checksum_valid = 1'b1; checksum_ok = 1'b0; // this one FAILS checksum, on purpose
        @(posedge clk);
        checksum_valid = 1'b0;
        tlast = 1'b1;
        @(posedge clk);
        tlast = 1'b0;
        check(metadata_valid == 1'b1, "S6a: first packet of the pair emits");
        check(metadata[1] == 1'b0, "S6a: checksum_ok bit correctly reflects a failed checksum");

        drive_fields(B_SRC, B_DST, B_TLEN, B_PROTO, B_TTL, B_DSCP, B_ECN, B_IHL);
        capture_done = 1'b1;
        @(posedge clk);
        capture_done = 1'b0;
        @(posedge clk);
        checksum_valid = 1'b1; checksum_ok = 1'b1; // this one PASSES
        @(posedge clk);
        checksum_valid = 1'b0;
        tlast = 1'b1;
        @(posedge clk);
        tlast = 1'b0;
        check(metadata_valid == 1'b1, "S6b: second packet emits independently");
        check(metadata[1] == 1'b1, "S6b: second packet's checksum_ok bit is 1, not leaked from packet A's fail");
        check_metadata(B_SRC, B_DST, B_TLEN, B_PROTO, B_TTL, B_DSCP, B_ECN, B_IHL, 1'b1, 1'b1, "S6b");

        @(posedge clk);
        if (errors == 0) $display("\n[TB] ALL CHECKS PASSED");
        else              $display("\n[TB] %0d CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
