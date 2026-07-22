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
    fifo #(
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

    // TEST 1. Push 5 elements in FIFO
    task test_push_FIFO();
        $display("============================");
        $display("   TEST 1 : Writing test    ");
        $display("============================");
        $display("[TB] --- Writing 5 items ---");

        // Setup the write
        m_axis_tready = 1'b0;   // Pause read side
        s_axis_tvalid = 1'b1;
        s_axis_tkeep  = 8'hFF;

        // Push the 5 items
        for (int i = 0; i < 5; i++) begin
            s_axis_tdata = 64'(i);
            s_axis_tlast = (i == 4) ? 1'b1 : 1'b0; // Set tlast on the last loop
            @(posedge clk);
        end
        s_axis_tvalid = 1'b0;

        // Let it sit in the FIFO for a bit
        $display("[TB] --- Waiting for 5 cycles --- ");
        repeat(5) @(posedge clk);

        // Read and check the 5 items
        $display("[TB] --- Reading 5 items ---");
        m_axis_tready = 1'b1; // Turn read side on

        for (int i = 0; i < 5; i++) begin
            if (m_axis_tdata == 64'(i)) begin
                $display("[TB] PASS: Read item correctly! Data: 0x%0h", m_axis_tdata);
            end else begin
                $error("[TB] FAIL: Expected 0x%0h, Got 0x%0h", i, m_axis_tdata);
            end

            @(posedge clk);
        end
        m_axis_tready = 1'b0;
    endtask

    // TEST 2. Boundary Test Task
    task test_fifo_full_boundary();
        int items_pushed;

        $display("=======================================");
        $display("   TEST 2: Writing to Full Fifo test   ");
        $display("=======================================");
        $display("[TB] --- Starting Boundary Test: Filling FIFO ---");
        
        items_pushed = 0;

        // Pause reading so the FIFO fills up
        m_axis_tready = 1'b0; 
        s_axis_tvalid = 1'b1;
        s_axis_tkeep  = 8'hFF;

        // Keep writing until the FIFO deasserts s_axis_tready
        while (1) begin
            s_axis_tdata = 64'(items_pushed);
            s_axis_tlast = 1'b0;
            
            // Evaluate if the FIFO is ready BEFORE the clock edge happens
            if (s_axis_tready == 1'b1) begin
                @(posedge clk); // Clock edge happens: Handshake is successful!
                items_pushed++;
            end else begin
                // FIFO is no longer ready. It is full!
                $display("[TB] FIFO Full! Stopped pushing. Total items pushed: %0d", items_pushed);
                break; // Break out of the while loop
            end
        end

        // Try to push one more item while the FIFO is full
        $display("[TB] --- Attempting to push an extra item while full ---");
        s_axis_tvalid = 1'b1;
        s_axis_tdata  = 64'hDEADBEEF; // A recognizable extra item

        // Wait 3 clock cycles.
        // Extra item should NOT overwrite anything in FIFO
        repeat(3) @(posedge clk);

        if (s_axis_tready !== 1'b0) begin
            $error("[TB] FAIL: tready should still be 0!");
        end

        // Empty the FIFO and verify every single item (including DEADBEEF)
        $display("[TB] --- Emptying FIFO and verifying original items + the extra item ---");
        m_axis_tready = 1'b1;

        for (int j = 0; j < items_pushed + 1; j++) begin
            // Wait if the FIFO isn't outputting valid data yet
            while (m_axis_tvalid == 1'b0) begin
                @(posedge clk);
            end

            // When first item is read, spot opens up in FIFO and DEADBEEF is read
            // Pull valid low to not push infinite "DEADBEEF" items
            if (j == 1) begin
                s_axis_tvalid = 1'b0;
            end

            // Verify data
            if (j < items_pushed) begin
                // Checking the original items
                if (m_axis_tdata == 64'(j)) begin
                    $display("[TB] PASS: Read original item %0d correctly", j);
                end else begin
                    $error("[TB] FAIL: Data mismatch at item %0d! Expected: 0x%0h, Got: 0x%0h", j, 64'(j), m_axis_tdata);
                end
            end else begin
                if (m_axis_tdata == 64'hDEADBEEF) begin
                    $display("[TB] PASS: Read the extra DEADBEEF item correctly! No data was lost.");
                end else begin
                    $error("[TB] FAIL: Expected the extra item 0xDEADBEEF, Got: 0x%0h", m_axis_tdata);
                end
            end

            @(posedge clk);
        end

        m_axis_tready = 1'b0; // Stop reading
        $display("[TB] --- Boundary Test Complete ---");
    endtask

    // TEST 3. Empty Boundary Test Task
    task automatic test_fifo_empty_boundary();
        begin
            int i;
        
            $display("=======================================");
            $display("   TEST 3: Empty Fifo Boundary Test    ");
            $display("=======================================");

            // Push 5 items in
            $display("[TB] --- Pushing 5 items in fifo ---");
            m_axis_tready = 1'b0;
            s_axis_tvalid = 1'b1;
            s_axis_tkeep = 8'hFF;

            for (i = 0; i < 5; i++) begin
                s_axis_tdata = 64'(i);
                s_axis_tlast = (i == 4) ? 1'b1 : 1'b0;
                @(posedge clk);
            end
            s_axis_tvalid = 1'b0;

            // Read the 5 items out
            $display("[TB] --- Reading 5 items out of fifo");
            m_axis_tready = 1'b1;
            for (i = 0; i < 5; i++) begin
                while (m_axis_tvalid == 1'b0) begin
                    @(posedge clk);
                end

                if (m_axis_tdata == 64'(i)) begin
                    $display("[TB] PASS: Read item %0d correctly", i);
                end else begin
                    $error("[TB] FAIL: Data mismatch on item %0d!", i);
                end
                @(posedge clk);
            end

            // FIFO should be empty now fingers crossed,  what if we try to read it now ?
            $display("[TB] --- Attempting to read empty FIFO ---");
            // Leave m_axis_tready = 1, FIFO should in theory pull m_axis_tvalid low.
            repeat(3) begin
                if (m_axis_tvalid !== 1'b0) begin
                    $error("[TB] FAIL: tvalid should be 0 when FIFO is empty !");
                end
                @(posedge clk);
            end
            $display("[TB] PASS: FIFO safely prevented underflow. tvalid = 0");

            // Push a new item while read is still active to see if it falls through immediately (goes to output immediately)
            // This is called FWFT fall-through
            s_axis_tvalid = 1'b1;
            s_axis_tdata = 64'hDEADBEEF;
            s_axis_tlast = 1'b1;

            // Wait for the write to complete
            do begin
                @(posedge clk);
            end while (s_axis_tready == 1'b0);
            s_axis_tvalid = 1'b0;

            // Wait for it to fall through to the output
            while (m_axis_tvalid == 1'b0) begin
                @(posedge clk);
            end

            if (m_axis_tdata == 64'hDEADBEEF) begin
                $display("[TB] PASS: New item fell through immediately. Data: 0x%0h", m_axis_tdata);
            end else begin
                $error("[TB] FAIL: Expected 0xDEADBEEF, got 0x%0h", m_axis_tdata);
            end

            @(posedge clk);

            // Clean up signals
            s_axis_tvalid = 1'b0;
            m_axis_tready = 1'b0;
            $display("[TB] --- Empty Boundary Test Complete ---");
        end
    endtask

    // TEST 4. Simultaneous read and write
    task automatic test_fifo_simultenous_read_and_write();
        begin
            int write_val, read_val, max_items;
            logic write_handshake, read_handshake;
            
            $display("==========================================");
            $display("   TEST 4: Simulataneous Read/Write Test  ");
            $display("==========================================");
            $display("[TB] --- Streaming items continuously ---");

            // Initialize variables
            write_val = 0;
            read_val = 0;
            max_items = 50;

            // Leave read side permanently ON (kinda like fast downstream flow)
            m_axis_tready = 1'b1;
            s_axis_tkeep = 8'hFF;

            // Loop until all 50 items have been outputed
            while (read_val < max_items) begin
                // Write Signals
                if (write_val < max_items) begin
                    s_axis_tvalid = 1'b1;
                    s_axis_tdata = 64'(write_val);
                    s_axis_tlast = (write_val == max_items - 1) ? 1'b1 : 1'b0;
                end else begin
                    s_axis_tvalid = 1'b0;
                end

                // Get status before clock edge
                write_handshake = s_axis_tvalid & s_axis_tready;
                read_handshake = m_axis_tvalid & m_axis_tready;

                // Verify data before clock edge
                if (read_handshake) begin
                    if (m_axis_tdata !== 64'(read_val)) begin
                        $error("[TB] FAIL: Data mismatch... expected 0x%0h", 64'(read_val), m_axis_tdata);
                    end
                end

                // Trigger the clock edge
                @(posedge clk);

                // Update counters after clock edge
                if (write_handshake) write_val++;
                if (read_handshake) read_val++;
            end

            // Clean up
            s_axis_tvalid = 1'b0;
            m_axis_tready = 1'b0;
            
            $display("[TB] PASS: Successfully wrote and read %0d items simultaneously!", max_items);
            $display("[TB] --- Simultaneous Read/Write Test Complete ---");
        end
    endtask

    // TEST 5. Sudden Reset Test
    task automatic test_fifo_sudden_reset();
        begin
            int i;
        
            $display("====================================");
            $display("   TEST 5: Suddent Reset Test       ");
            $display("====================================");
            
            // Push 3 items into the FIFO
            $display("[TB] --- Pushing 3 items before reset ---");
            m_axis_tready = 1'b0; 
            s_axis_tvalid = 1'b1;
            s_axis_tkeep  = 8'hFF;

            for (i = 0; i < 3; i++) begin
                s_axis_tdata = 64'(i + 100);
                s_axis_tlast = 1'b0;
                @(posedge clk);
            end
            s_axis_tvalid = 1'b0;

            // Wait a few cycles so the data settles inside the RAM
            repeat(2) @(posedge clk);

            // Trigger the Asynchronous Reset
            $display("[TB] --- Triggering reset ---");
            rst_n = 1'b0;

            // Wait a couple of clock cycles while reset is active
            repeat(2) @(posedge clk);

            // Verify the output is safely nullified
            // Even if m_axis_tready == 0, the FIFO must pull valid low during a reset
            if (m_axis_tvalid !== 1'b0) begin
                $error("[TB] FAIL: tvalid did not drop to 0 during reset!");
            end else begin
                $display("[TB] PASS: tvalid safely dropped to 0.");
            end

            // 4. Release Reset
            rst_n = 1'b1;
            $display("[TB] --- Reset released. Checking recovery ---");
            
            // Wait a cycle for the synchronous logic to stabilize
            @(posedge clk);
            
            if (m_axis_tvalid !== 1'b0) begin
                $error("[TB] FAIL: FIFO output garbage data after reset was released!");
            end
            
            // 5. Push a new item to ensure the pointers reset correctly
            $display("[TB] --- Pushing new data to verify recovery ---");
            s_axis_tvalid = 1'b1;
            s_axis_tdata  = 64'hDEADBEEF; 
            
            do begin
                @(posedge clk);
            end while (s_axis_tready == 1'b0);
            s_axis_tvalid = 1'b0;
            
            // Read and verify the new item
            m_axis_tready = 1'b1;
            while (m_axis_tvalid == 1'b0) begin
                @(posedge clk);
            end
            
            // If the pointers didn't reset, we would read the old '100' data here instead of DEADBEEF
            if (m_axis_tdata == 64'hDEADBEEF) begin
                $display("[TB] PASS: FIFO recovered and successfully routed new data: 0x%0h", m_axis_tdata);
            end else begin
                $error("[TB] FAIL: Expected 0xDEADBEEF, got 0x%0h", m_axis_tdata);
            end
            
            @(posedge clk); // Finish the handshake
            
            m_axis_tready = 1'b0;
            $display("[TB] --- Sudden Reset Test Complete ---");
        end
    endtask

    // TEST 6. Packet Boundary (tlast) Test
    task automatic test_fifo_packet_boundary();
    begin
        int i;
        int packet_len;
        
        $display("=======================================");
        $display("   TEST 6: Packet Boundary tlast Test  ");
        $display("=======================================");
        
        packet_len = 8;
        
        // Push a packet into the FIFO
        $display("[TB] --- Pushing an %0d-beat packet ---", packet_len);
        m_axis_tready = 1'b0; 
        s_axis_tvalid = 1'b1;
        s_axis_tkeep  = 8'hFF;
        
        for (i = 0; i < packet_len; i++) begin
            s_axis_tdata = 64'hAAAA_0000_BBBB_0000 + i;
            
            // tlast is only high on the final beat of the packet
            if (i == packet_len - 1) begin
                s_axis_tlast = 1'b1;
            end else begin
                s_axis_tlast = 1'b0;
            end
            
            // Wait for handshake
            do begin
                @(posedge clk);
            end while (s_axis_tready == 1'b0);
        end
        
        s_axis_tvalid = 1'b0;
        s_axis_tlast  = 1'b0; // Clean up the input bus
        
        // Read the packet out and verify tlast is perfectly synchronized
        $display("[TB] --- Reading packet and verifying tlast ---");
        m_axis_tready = 1'b1;
        
        for (i = 0; i < packet_len; i++) begin
            while (m_axis_tvalid == 1'b0) begin
                @(posedge clk);
            end
            
            // Verify Data
            if (m_axis_tdata !== (64'hAAAA_0000_BBBB_0000 + i)) begin
                $error("[TB] FAIL: Data mismatch at beat %0d! Expected 0x%0h, Got 0x%0h", i, (64'hAAAA_0000_BBBB_0000 + i), m_axis_tdata);
            end
            
            // Verify tlast Synchronization
            if (i == packet_len - 1) begin
                // This is the last beat. tlast should be 1.
                if (m_axis_tlast !== 1'b1) begin
                    $error("[TB] FAIL: tlast did NOT assert on the final beat (beat %0d)!", i);
                end else begin
                    $display("[TB] PASS: Beat %0d - Data correct AND tlast asserted properly.", i);
                end
            end else begin
                // This is an intermediate beat. tlast should be 0.
                if (m_axis_tlast !== 1'b0) begin
                    $error("[TB] FAIL: tlast asserted early on beat %0d!", i);
                end else begin
                    $display("[TB] PASS: Beat %0d - Data correct (tlast = 0).", i);
                end
            end
            
            @(posedge clk); // Finish read handshake
        end
        
        m_axis_tready = 1'b0;
        $display("[TB] --- Packet Boundary Test Complete ---");
    end
    endtask

    // TEST 7. Random Backpressure Test
    task automatic test_fifo_random_backpressure_test();
    begin
        int write_val, read_val, max_items;
        logic write_handshake, read_handshake;
        int write_prob, read_prob;
        logic is_stalled;

        $display("======================================");
        $display("   TEST 7: Random Backpressure Test   ");
        $display("======================================");
        $display("[TB] --- Streaming 100 items with random stalls ---");

        write_val = 0;
        read_val  = 0;
        max_items = 100;

        // Set initial conditions
        s_axis_tvalid = 1'b0;
        m_axis_tready = 1'b0;
        s_axis_tkeep  = 8'hFF;
        s_axis_tlast  = 1'b0;

        // Wait a full cycle to let the initial state settle
        @(posedge clk);

        while (read_val < max_items) begin
            // Wait for the clock edge
            @(posedge clk);

            // Evaluate Handshakes
            write_handshake = s_axis_tvalid & s_axis_tready;
            read_handshake  = m_axis_tvalid & m_axis_tready;

            // Verify data & update counters
            if (read_handshake) begin
                if (m_axis_tdata !== 64'(read_val)) begin
                    $error("[TB] FAIL: Data mismatch! Expected 0x%0h, Got 0x%0h", 64'(read_val), m_axis_tdata);
                end
                read_val++;
            end

            if (write_handshake) begin
                write_val++;
            end

            // Determine next state
            // If we asserted valid but didn't handshake, we MUST hold data.
            is_stalled = (s_axis_tvalid == 1'b1 && write_handshake == 1'b0);

            // Drive new inputs using (<=)
            // This guarantees the signals update properly for the NEXT cycle's active region.
            read_prob = $urandom() % 100;
            m_axis_tready <= (read_prob < 60) ? 1'b1 : 1'b0;

            if (write_val < max_items) begin
                if (is_stalled) begin
                    // AXI RULE: Do nothing. The non-blocking assignments will just hold their previous state.
                end else begin
                    // We are free to change the bus!
                    write_prob = $urandom() % 100;
                    s_axis_tvalid <= (write_prob < 70) ? 1'b1 : 1'b0;
                    
                    if (write_prob < 70) begin
                        s_axis_tdata <= 64'(write_val);
                        s_axis_tlast <= (write_val == max_items - 1) ? 1'b1 : 1'b0;
                    end
                end
            end else begin
                // All items written. Turn off the transmitter.
                s_axis_tvalid <= 1'b0;
            end
        end

        // Clean up
        s_axis_tvalid <= 1'b0;
        m_axis_tready <= 1'b0;
        
        $display("[TB] PASS: Successfully streamed %0d items through random traffic!", max_items);
        $display("[TB] --- Random Backpressure Test Complete ---");
    end
    endtask

    // Main Test Flow
    initial begin
        $display("============================================");
        $display("   STARTING FWFT FIFO VERIFICATION          ");
        $display("============================================");

        reset_env();

        // Tests
        test_push_FIFO();
        test_fifo_full_boundary();
        test_fifo_empty_boundary();
        test_fifo_simultenous_read_and_write();
        test_fifo_sudden_reset();
        test_fifo_packet_boundary();
        test_fifo_random_backpressure_test();

        // End of simulation summary
        $display("============================================");
        $display("   SIMULATION COMPLETED");
        $display("============================================");
        $finish;
    end
endmodule

/*
VERILATOR COMMAND TEST
verilator --binary -j 0 --timing --trace --trace-structs -Wall -Wno-fatal RTL/IP_Parser/ip_parser_input_fifo.sv verification/IP_Parser/tb_ip_input_fifo.sv --top-module tb_ip_parser_input_fifo

RUN TEST
./obj_dir/Vtb_ip_parser_input_fifo
*/
