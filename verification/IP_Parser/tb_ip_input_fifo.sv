`timescale 1ns/1ps

//==========================================
// Testbench for IP Parser Input fifo
//==========================================

module tb_ip_parser_input_fifo ();
    // Parameters and Clock/Reset Generation
    parameter DEPTH = 16; // Smaller than RTL for faster simulation
    parameter ADDRW = $clog2(DEPTH);
    localparam DATAW = 64 + 8 + 1 + 1;

    logic clk, rst_n;

    // 100 MHz Clock generation
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // DUT Interface Signals
    logic [63:0]    s_axis_tdata;
    logic [7:0]     s_axis_tkeep;
    logic           s_axis_tvalid;
    logic           s_axis_tready;
    logic           s_axis_tlast;
    logic [0:0]     s_axis_tuser;

    logic [63:0]    m_axis_tdata;
    logic [7:0]     m_axis_tkeep;
    logic           m_axis_tvalid;
    logic           m_axis_tready;
    logic           m_axis_tlast;
    logic [0:0]     m_axis_tuser;

    // DUT Instantiation
    ip_parser_input_fifo #(
        .DEPTH(DEPTH),
        .ADDRW(ADDRW)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .s_axis_tdata(s_axis_tdata),
        .s_axis_tkeep(s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast(s_axis_tlast),
        .s_axis_tuser(s_axis_tuser),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast),
        .m_axis_tuser(m_axis_tuser)
    );

    // Score and test tracking
    integer errors = 0;
    integer i;
 
    // Used by the random back-and-forth in Test 4 below
    localparam RANDOM_ITEMS = 30;
    integer write_val, read_val;
    logic   write_handshake, read_handshake;


    task reset_env();
        rst_n = 0;
        s_axis_tvalid = 0;
        s_axis_tdata = '0;
        s_axis_tkeep = '0;
        s_axis_tlast = 0;
        s_axis_tuser = 0;
        m_axis_tready = 1;
        repeat(5) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
        $display("[TB] System Reset Complete.");
    endtask

    // Small if/else helper borrowed from tb_ip_parser_header_extraction.sv
    task check(input cond, input string msg);
        if (cond)
            $display("PASS: %0s", msg);
        else begin
            $display("FAIL: %0s", msg);
            errors = errors + 1;
        end
    endtask


    // Main Test Flow
    initial begin
        // Dump a waveform so we can look at this in GTKWave afterward
        $dumpfile("tb_ip_parser_input_fifo.vcd");
        $dumpvars(0, tb_ip_parser_input_fifo);

        // Reset
        reset_env();

        // =============================================
        // Test 1: Write 5 words, read them out in order
        // =============================================
        $display("\n[TB] === Test 1: Basic Read/Write ===");

        s_axis_tvalid   = 1;
        s_axis_tkeep    = 8'hFF;
        m_axis_tready   = 0;

        for (i = 0; i < 5; i = i + 1) begin
            s_axis_tdata = i;
            s_axis_tlast = (i == 4);
            @(posedge clk);
        end
        s_axis_tvalid = 0;
        s_axis_tlast = 0;

        // Let the words sit in the FIFO for a bit
        repeat (3) @(posedge clk);

        m_axis_tready = 1;
        for (i = 0; i < 5; i = i + 1) begin
            while (!m_axis_tvalid)
                @(posedge clk);
            check(m_axis_tdata == i, "Word came back in the right order ?");
            @(posedge clk);
        end
        m_axis_tready = 0;

        repeat (2) @(posedge clk);
        check(m_axis_tvalid == 0, "tvalid drops once the FIFO is empty");

        // Atp, the FIFO should be empty, let's leave tready high and
        // make sure nothing weird comes out while there's nothing to read
        m_axis_tready = 1;
        repeat (5) @(posedge clk);
        check(m_axis_tvalid == 0, "tvalid stays low when reading from an Empty FIFO");
        m_axis_tready = 0;

        // =============================================
        // Test 2: Fill FIFO, meaning tready should drop
        // =============================================
        $display("\n[TB] === Test 2: Fill FIFO until full ===");

        m_axis_tready = 0;      // Don't drain while filling the FIFO
        s_axis_tvalid = 1;
        s_axis_tkeep = 8'hFF;
        i = 0;

        while (s_axis_tready && i <= DEPTH + 1) begin
            s_axis_tdata = i;
            @(posedge clk);
            i = i + 1;
        end

        check(i == DEPTH + 1, "tready dropped after exactly DEPTH words (i.e. when FIFO is full)");

        // FIFO should be full now (s_axis_tready == 0)
        // Let's try to push one more word
        // In theory, it should be rejected and not stored in the FIFO
        s_axis_tdata = 64'hDEAD_BEEF;
        repeat (3) @(posedge clk);
        check(s_axis_tready == 0, "tready stays low while pushing into a full FIFO");
        s_axis_tvalid = 0;

        // Drain it back out and make sure DEADBEEF doesn't show up
        // If it does, the extra word overwrote something :skull:
        m_axis_tready = 1;
        for (i = 0; i < DEPTH + 1; i = i + 1) begin
            while (!m_axis_tvalid)
                @(posedge clk);
            check (m_axis_tdata == i, "drained word matches original data => extra word not stored in FIFO");
            @(posedge clk);
        end
        m_axis_tready = 0;

        // ===============================================
        // Test 3: Reset while transfer is still happening
        // ===============================================
        $display("\n [TB] === Test 3: What happens when reset in middle of a transfer ===");

        s_axis_tvalid = 1;
        s_axis_tkeep  = 8'hFF;
        s_axis_tdata  = 64'hAA;
        @(posedge clk);
        s_axis_tdata  = 64'hBB;
        @(posedge clk);
        s_axis_tvalid = 0;

        rst_n = 0;
        repeat (2) @(posedge clk);
        check(m_axis_tvalid == 0, "tvalid low during reset");

        rst_n = 1;
        @(posedge clk);

        // Let's try to push one new word after reset !
        // If pointers didn't actually reset, we would get something mixed up with old AA/BB data
        s_axis_tvalid = 1;
        s_axis_tdata = 64'hCC;
        @(posedge clk);
        s_axis_tvalid = 0;

        m_axis_tready = 1;
        while (!m_axis_tvalid)
            @(posedge clk);
        check(m_axis_tdata == 64'hCC, "FIFO reset cleanly");
        @(posedge clk);
        m_axis_tready = 0;

        // =============================================
        // Test 4: Random back-and-forth read and writes
        // =============================================
        $display("\n [TB] === Test 4: Random read/writes ===");

        write_val = 0;
        read_val  = 0;
        s_axis_tkeep  = 8'hFF;
        s_axis_tlast  = 0;

        while (read_val < RANDOM_ITEMS) begin
            // Randomly decide whether to offer a push and accept a pop
            s_axis_tvalid = (write_val < RANDOM_ITEMS) && ($random % 2 == 0);
            m_axis_tready = ($random % 2 == 0);
            if (s_axis_tvalid)
                s_axis_tdata = write_val;
 
            write_handshake = s_axis_tvalid && s_axis_tready;
            read_handshake  = m_axis_tvalid && m_axis_tready;
 
            if (read_handshake)
                check(m_axis_tdata == read_val, "random test: words came back in order");
 
            @(posedge clk);
 
            if (write_handshake) write_val = write_val + 1;
            if (read_handshake)  read_val  = read_val + 1;
        end

        s_axis_tvalid = 0;
        m_axis_tready = 0;

        // --- Summary ---
        if (errors == 0)
            $display("\nALL TESTS PASSED");
        else
            $display("\n%0d TEST(S) FAILED", errors);

        $finish;
    end
endmodule

/*
VERILATOR COMMAND TEST
verilator --binary -j 0 --timing --trace --trace-structs -Wall -Wno-fatal RTL/IP_Parser/ip_parser_input_fifo.sv verification/IP_Parser/tb_ip_input_fifo.sv --top-module tb_ip_parser_input_fifo

RUN TEST
./obj_dir/Vtb_ip_parser_input_fifo
*/
