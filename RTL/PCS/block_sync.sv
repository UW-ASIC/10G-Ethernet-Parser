module block_sync_rx #(

    parameter HEAD_W = 2
)(
    input  logic          clk,
    input  logic        rst_n,

    // from GTY SerDes (directly, same signal also goes to gearbox)
    
    input  logic                i_serdes_v,   // serdes data is valid (CDR locked)

    // from gearbox
    input  logic                   i_valid,   // gearbox has a valid 66-bit block ready this cycle (flag to read header)
    input  logic [HEAD_W - 1 : 0]   i_head,   // 2-bit sync header to check

    // to gearbox
    output logic                    o_slip,   // tell gearbox to shift alignment by 1 bit

    // status
    output logic                    o_lock    // alignment found and confirmed
);

    // this module acts as a simple state machine, taking sync headers from the
    // gearbox and evaluating alignment accuracy.

    logic [10 : 0] counter; //Count 64 valid header

    logic [6 : 0] bad_header_count; //Count Invalid Headers
    logic [10 : 0] good_header_count; //Count Valid Headers
  

    logic [HEAD_W - 1 : 0] header;   // 2-bit sync header to check

    typedef enum logic [1 : 0]{
        LOCK_LOST = 2'b00,
        BLOCK_LOCK = 2'b01
    } state;

    state current_state, next_state;

    logic [6 : 0] bad_next;
    logic [10 : 0] good_next;

    always_ff @(posedge clk) begin
        if (!rst_n) begin // If not reset
            o_lock <= 1'b0;
            current_state <= LOCK_LOST;
            counter <= 11'b0;
            good_header_count <= 11'b0;
            bad_header_count <= 7'b0;
        end else begin // If reset
            if(!i_serdes_v) begin  //If serdes does not send active frames
                current_state <= LOCK_LOST; 
                counter <= 11'b0;
                good_header_count <= 11'b0;
                bad_header_count <= 7'b0;
                o_lock <= 1'b0;
            end else if (i_valid) begin //If there is a valid 66 bit block ready
                current_state <= next_state;
                o_lock <= (next_state == BLOCK_LOCK);

                if (current_state == BLOCK_LOCK) begin //Count good vs bad headers when in BLOCK_LOCK state
                    if(good_next + bad_next == 11'd1024) begin
                        good_header_count <= 11'b0;
                        bad_header_count <= 7'b0;
                    end else begin
                        good_header_count <= good_next;
                        bad_header_count <= bad_next;
                    end
                end

                if (current_state == BLOCK_LOCK && next_state == LOCK_LOST) begin //During trasition between states
                    good_header_count <= 11'b0;
                    bad_header_count <= 7'b0;
                    counter <= 11'b0;
                end else if (header[1] ^ header[0]) begin //If header is valid
                    counter <= counter + 1;
                end else begin //Reset counter
                    counter <= 11'b0;
                end

            end else begin
                //Nothing happens
            end
        end
    end

    always_comb begin
        o_slip = 1'b0;
        next_state = current_state;
        header = i_head;
        good_next = good_header_count + (header[1] ^ header[0]);
        bad_next = bad_header_count + !(header[1] ^ header[0]);
        case (current_state)
            LOCK_LOST: begin
                if ((header[1] ^ header[0]) && counter == 7'h3F) begin //Previous 63 headers valid and 64th also valid so change state
                    next_state = BLOCK_LOCK;
                end else if (!(header[1] ^ header[0])) begin //If bad header, assert o_slip
                    if (i_valid) o_slip = 1'b1;
                end
            end
            BLOCK_LOCK: begin
                if(bad_next > 7'd64) begin //If bad headers greater than 64 (i.e. 65 or more) within the 1024-header window
                    next_state = LOCK_LOST;
                    if (i_valid) o_slip = 1'b1;
                end
            end
            default: next_state = LOCK_LOST; //Always default back to LOST_LOCK state
        endcase
        // o_slip is only ever asserted above when i_valid is set, so it can never glitch on a stale/garbage i_head.
        
    end

   

    /* once serdes data is valid (i_signal_ok from serdes) and gearbox has valid headers to share
        (i_valid from gearbox_rx), start checking headers and counting:
        we expect to see valid headers (01 or 10) 64 times in a row to initially declare BLOCK_LOCK.
        if at any point during acquisition we see an invalid header (00 or 11), assert o_slip and reset.

        Once locked, we track good vs. bad headers over a rolling window of 1024 headers; if 65 or
        more invalid headers occur within that window, we assert o_slip, drop lock, and restart
        acquisition from scratch.

        This function brute forces an alignment search until we find the correct offset and lock.
        We maintain lock until reset, signal loss, or excessive errors. any further errors downstream (invalid block types, corrupted data) are handled by the decoder. */
  
    // * hint: header validation is a single XOR.


endmodule