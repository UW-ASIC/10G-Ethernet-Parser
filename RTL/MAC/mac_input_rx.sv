`default_nettype none

module mac_input_rx (
    input  logic        clk,
    input  logic        rst_n,

    // Input from async FIFO from 10G-Base-R PCS and AXL_S to Frame Parser
    input  logic        axls_tready,    // backpressure from the Frame parser
    input  logic [83:0] PCS_out,        // 84 bit FIFO transport

    // Output to CRC and AXL_S to Frame Parser
    output logic [63:0] tdata,          // 64 bytes of data
    output logic [7:0]  tkeep,          // Data indicator, `0xFF` on every beat except the last
    output logic [63:0] data,           // 8 bytes of XGMII data. Raw frame content: preamble bytes, header bytes, payload bytes, FCS bytes, or idle characters depending on where we are in the frame.
    output logic [7:0]  ctrl,           // Control bit per byte, byte `n` in tdata where `ctrl[n]` = 1, type = (Idle, Start, Terminate, Error); `ctrl[n]` = 0, type = (data byte).
    output logic [7:0]  keep,           // Valid bytes in this beat. all ones during normal data beats, partial on terminate beats where the frame ends mid-word.
    output logic        start,          // High on the beginning of a new Ethernet frame
    output logic        idle,           // High when all 8 bytes are Idle (0x07). this is what the link looks like between frames
    output logic        terminate,      // High on the end of the current frame
    output logic        error           // High when PCS decoder encountered an invalid sync header or unrecognized block type
);

    logic [63:0] data_buffer;
    logic [7:0]  ctrl_buffer;
    logic [7:0]  keep_buffer;
    logic        start_buffer;
    logic        idle_buffer;
    logic        terminate_buffer;
    logic        error_buffer;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_buffer      <= 64'b0;
            ctrl_buffer      <= 8'b0;
            keep_buffer      <= 8'b0;
            start_buffer     <= 1'b0;
            idle_buffer      <= 1'b0;
            terminate_buffer <= 1'b0;
            error_buffer     <= 1'b0;
        end else begin
            if (axls_tready) begin
                data_buffer      <= PCS_out[63:0];
                ctrl_buffer      <= PCS_out[71:64];
                keep_buffer      <= PCS_out[79:72];
                start_buffer     <= PCS_out[80];
                idle_buffer      <= PCS_out[81];
                terminate_buffer <= PCS_out[82];
                error_buffer     <= PCS_out[83];
            end
        end
    end

    assign data      = data_buffer;
    assign ctrl      = ctrl_buffer;
    assign keep      = keep_buffer;
    assign start     = start_buffer;
    assign idle      = idle_buffer;
    assign terminate = terminate_buffer;
    assign error     = error_buffer;

    assign tdata     = data_buffer;
    assign tkeep     = keep_buffer;

endmodule
`default_nettype wire
