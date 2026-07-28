`timescale 1ns / 1ps

// tb for ip_parser_header_extraction - drives beats straight onto m_axis_*
// (this module sits right after the fifo, so from its POV that's the slave
// side of the stream) and checks the captured fields + capture_done/
// header_incomplete timing.

module tb_ip_parser_header_extraction;

    logic clk, rst_n;

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    logic [63:0] m_axis_tdata;
    logic [7:0]  m_axis_tkeep;
    logic        m_axis_tvalid;
    logic        m_axis_tready;
    logic        m_axis_tlast;
    logic [0:0]  m_axis_tuser;

    logic        capture_done;
    logic        header_incomplete;
    logic [3:0]  version;
    logic [3:0]  ihl;
    logic [5:0]  dscp;
    logic [1:0]  ecn;
    logic [15:0] total_len;
    logic [7:0]  ttl;
    logic [7:0]  protocol;
    logic [31:0] src_ip;
    logic [31:0] dst_ip;

    ip_parser_header_extraction dut (
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

    // known-good header, fields picked so each one is easy to eyeball in a
    // waveform (no accidental collisions between fields)
    localparam [3:0]  EXP_VERSION = 4'h4;
    localparam [3:0]  EXP_IHL     = 4'h5;
    localparam [5:0]  EXP_DSCP    = 6'h0A;
    localparam [1:0]  EXP_ECN     = 2'h1;
    localparam [15:0] EXP_TOTLEN  = 16'd60;
    localparam [7:0]  EXP_TTL     = 8'd64;
    localparam [7:0]  EXP_PROTO   = 8'd17; // UDP
    localparam [31:0] EXP_SRC_IP  = 32'hC0A8_0101; // 192.168.1.1
    localparam [31:0] EXP_DST_IP  = 32'hC0A8_0102; // 192.168.1.2

    localparam [63:0] BEAT0 = {EXP_VERSION, EXP_IHL, EXP_DSCP, EXP_ECN, EXP_TOTLEN, 16'h0001, 16'h0000};
    localparam [63:0] BEAT1 = {EXP_TTL, EXP_PROTO, 16'hBEEF, EXP_SRC_IP};
    localparam [63:0] BEAT2 = {EXP_DST_IP, 32'hDEAD_BEEF};

    // a second header, distinct from the first, used for the back-to-back test
    localparam [31:0] EXP2_SRC_IP = 32'h0A00_0001;
    localparam [31:0] EXP2_DST_IP = 32'h0A00_0002;
    localparam [63:0] BEAT0_B = {4'h4, 4'h5, 6'h00, 2'h0, 16'd20, 16'h0002, 16'h0000};
    localparam [63:0] BEAT1_B = {8'd128, 8'd6, 16'hCAFE, EXP2_SRC_IP};
    localparam [63:0] BEAT2_B = {EXP2_DST_IP, 32'h0000_0000};

    int errors = 0;

    task automatic check(logic cond, string msg);
        if (cond) $display("[TB] PASS: %s", msg);
        else begin
            $error("[TB] FAIL: %s", msg);
            errors++;
        end
    endtask

    task automatic drive_beat(input [63:0] tdata, input tlast);
        m_axis_tdata  = tdata;
        m_axis_tkeep  = 8'hFF;
        m_axis_tvalid = 1'b1;
        m_axis_tlast  = tlast;
    endtask

    task automatic send_beat(input [63:0] tdata, input tlast);
        drive_beat(tdata, tlast);
        @(posedge clk);
    endtask

    task automatic idle_beat();
        m_axis_tvalid = 1'b0;
        m_axis_tlast  = 1'b0;
        @(posedge clk);
    endtask

    task automatic reset_env();
        rst_n         = 1'b0;
        m_axis_tdata  = '0;
        m_axis_tkeep  = '0;
        m_axis_tvalid = 1'b0;
        m_axis_tlast  = 1'b0;
        m_axis_tuser  = '0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
    endtask

    initial begin
        reset_env();

        // =====================================================================
        // SCENARIO 1: full header (ihl=5), check every field + capture_done
        // lining up with dst_ip actually being valid (this is the off-by-one
        // that got fixed in ip_parser_header_extraction - if it regresses,
        // capture_done will read back 1 beat too early below and this fails)
        // =====================================================================
        $display("\n[TB] === SCENARIO 1: Full header capture ===");
        send_beat(BEAT0, 1'b0);
        send_beat(BEAT1, 1'b0); // dst_ip's beat hasn't even gone out yet
        check(capture_done == 1'b0, "capture_done stays low until the dst_ip beat actually completes");
        send_beat(BEAT2, 1'b1); // dst_ip beat, tlast on a clean 3-beat header
        check(capture_done == 1'b1, "capture_done pulses the same cycle dst_ip's new value lands");
        check(dst_ip    == EXP_DST_IP,  "dst_ip already holds the new value when capture_done pulses");
        check(version   == EXP_VERSION, "version");
        check(ihl       == EXP_IHL,     "ihl");
        check(dscp      == EXP_DSCP,    "dscp");
        check(ecn       == EXP_ECN,     "ecn");
        check(total_len == EXP_TOTLEN,  "total_len");
        check(ttl       == EXP_TTL,     "ttl");
        check(protocol  == EXP_PROTO,   "protocol");
        check(src_ip    == EXP_SRC_IP,  "src_ip");
        idle_beat();
        check(capture_done == 1'b0, "capture_done is a single-cycle pulse");

        // =====================================================================
        // SCENARIO 2: runt packet - tlast shows up before dst_ip's beat
        // =====================================================================
        $display("\n[TB] === SCENARIO 2: Runt packet (tlast before beat 2) ===");
        send_beat(BEAT0, 1'b0);
        drive_beat(BEAT1, 1'b1); // tlast while beat_cnt == 1, header never completes
        // header_incomplete is combinational off the live beat_cnt, so check it
        // while this beat is still on the bus, before the clock edge processes it.
        // #1 lets the DUT's assign chain settle - Verilator doesn't re-run
        // combinational logic just because we did a blocking assignment, only
        // when simulation time actually advances
        #1;
        check(header_incomplete == 1'b1, "header_incomplete asserted while the runt-ending beat is on the bus");
        @(posedge clk);
        check(capture_done == 1'b0, "capture_done never fires for a runt packet");
        idle_beat();
        check(capture_done == 1'b0, "capture_done stays low the cycle after too");

        // =====================================================================
        // SCENARIO 3: back-to-back packets, no bubble between them - beat_cnt
        // must reset off tlast and not leak scenario-1's fields into this one
        // =====================================================================
        $display("\n[TB] === SCENARIO 3: Back-to-back packets ===");
        send_beat(BEAT0_B, 1'b0);
        send_beat(BEAT1_B, 1'b0);
        send_beat(BEAT2_B, 1'b1);
        check(capture_done == 1'b1, "capture_done pulses for the second packet too");
        check(src_ip == EXP2_SRC_IP, "src_ip updated for the second packet");
        check(dst_ip == EXP2_DST_IP, "dst_ip updated for the second packet");

        idle_beat();
        if (errors == 0) $display("\n[TB] ALL CHECKS PASSED");
        else              $display("\n[TB] %0d CHECK(S) FAILED", errors);
        $finish;
    end

endmodule
