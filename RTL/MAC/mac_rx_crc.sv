`default_nettype none

module mac_rx_crc (
    input logic        clk,
    input logic        rst_n,

    // from mac_input_rx

    input logic [63:0] data,
    input logic [7:0]  ctrl,
    input logic [7:0]  keep,
    input logic        start,
    input logic        idle,
    input logic        terminate,
    input logic        error,

    // to AXI_S
    input logic         tready,
    output logic [63:0] tdata,
    output logic [7:0]  tkeep,
    output logic        tvalid,
    output logic        tlast,
    output logic        tuser
);

    localparam logic [31:0] CRC_OK = 32'h2144_DF1C;

    typedef enum logic [0:0] {ST_IDLE, ST_FORWARD} state_t;
    typedef enum logic [1:0] {PEND_NONE, PEND_EMIT_TRIMMED, PEND_SUPPRESS} pend_e;

    state_t state_q, state_d;

    //helpers
    function automatic logic [3:0] popcount8(input logic [7:0] v);
        logic [3:0] n;
        n = 0;
        for (int i = 0; i < 8; i++) n += v[i];
        return n;
    endfunction

    function automatic logic [7:0] keep_mask(input logic [3:0] n);
        logic [7:0] m;
        m = '0;
        for (int i = 0; i < 8; i++) m[i] = (i < n);
        return m;
    endfunction

    logic [3:0] nbytes;
    assign nbytes = popcount8(keep);

    //fsm
    always_comb begin
        state_d = state_q;
        unique case (state_q)
            ST_IDLE: if (start) state_d = ST_FORWARD;
            ST_FORWARD: if (terminate) state_d = ST_IDLE;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_q <= ST_IDLE;
        else if (tready) state_q <= state_d;
    end

    logic forwarding;
    assign forwarding = (state_q == ST_FORWARD);

    //crc core

    logic [31:0] o_crc;

    CRC_core crc_core_inst (
        .i_clk       (clk),
        .i_rstn      (rst_n),
        .i_8xframe     (data),
        .i_valid     (tready && forwarding),
        .i_last      (terminate),
        .i_corrupt   (error),
        .o_crc       (o_crc)
    );

    logic [63:0] data_d;
    logic [7:0]  keep_d;
    logic        valid_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin  
            valid_d <= 1'b0;
            data_d <= '0;
            keep_d <= '0;
        end 
        else if (tready) begin
            valid_d <= forwarding;
            data_d <= data;
            keep_d <= keep;
        end
    end

    logic [3:0] prev_nbytes_trimmed;
    logic       prev_is_last;

    always_comb begin
        prev_nbytes_trimmed = 4'd8;
        prev_is_last = 1'b0;

        if (forwarding && terminate) begin
            if (nbytes > 4'd4) begin
                prev_nbytes_trimmed = 4'd8;
                prev_is_last = 1'b0;
            end

            else begin
                prev_nbytes_trimmed = 4'd4 + nbytes;
                prev_is_last = 1'b1;
            end
        end
    end

    pend_e      pend_mode_q;
    logic [3:0] pend_nbytes_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend_mode_q <= PEND_NONE;
        end

        else if (tready) begin
            if (forwarding && terminate) begin
                if(nbytes > 4'd4) begin
                    pend_mode_q <= PEND_EMIT_TRIMMED;
                    pend_nbytes_q <= nbytes - 4'd4;
                end

                else begin 
                    pend_mode_q <= PEND_SUPPRESS;
                end
            end
            
            else begin
                pend_mode_q <= PEND_NONE;
            end
        end
    end

    // holding buffer
    logic final_capture;
    logic [1:0] final_capture_delay;
    logic [63:0] final_capture_data;
    logic [7:0] final_capture_keep;
    logic final_release;
    logic [63:0] final_data_q;
    logic [7:0] final_keep_q;

    assign final_capture = prev_is_last || (pend_mode_q == PEND_EMIT_TRIMMED);
    assign final_capture_delay = prev_is_last ? 2'd2 : 2'd1;
    assign final_capture_data = data_d;
    assign final_capture_keep = prev_is_last ? keep_mask(prev_nbytes_trimmed) : keep_mask(pend_nbytes_q);

    beat_hold_release #(
        .DATA_W(64), .KEEP_W(8), .DELAY_W(2)
    ) 
    final_beat_hold (
        .clk (clk),
        .rst_n (rst_n),
        .tready (tready),
        .capture (final_capture),
        .capture_delay (final_capture_delay),
        .capture_data (final_capture_data),
        .capture_keep (final_capture_keep),
        .release_valid (final_release),
        .release_data (final_data_q),
        .release_keep (final_keep_q)
    );

    //output

    always_comb begin
        tdata = data_d;
        tkeep = keep_mask(popcount8(keep_d));
        tvalid = valid_d;
        tlast = 1'b0;
        tuser = 1'b0;

        if (prev_is_last || pend_mode_q != PEND_NONE) begin
            tvalid = 1'b0;
        end

        if (final_release) begin
            tdata = final_data_q;
            tkeep = final_keep_q;
            tvalid = 1'b1;
            tlast = 1'b1;
            tuser = (o_crc != CRC_OK);
        end
    end
endmodule
`default_nettype wire