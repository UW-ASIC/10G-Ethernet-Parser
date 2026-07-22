`default_nettype none

module mac_output_tx (
    input  logic        clk,
    input  logic        rst_n,

    // Input from MAC
    input  logic        mac_tready,     // backpressure from the MAC

    // Inputs data from MAC
    input  logic [63:0] data,           // 8 bytes of XGMII data. Raw frame content: preamble bytes, header bytes, payload bytes, FCS bytes, or idle characters depending on where we are in the frame.
    input  logic [7:0]  ctrl,           // Control bit per byte, byte `n` in tdata where `ctrl[n]` = 1, type = (Idle, Start, Terminate, Error); `ctrl[n]` = 0, type = (data byte).
    input  logic [7:0]  keep,           // Valid bytes in this beat. all ones during normal data beats, partial on terminate beats where the frame ends mid-word.
    input  logic        start,          // High on the beginning of a new Ethernet frame
    input  logic        idle,           // High when all 8 bytes are Idle (0x07). this is what the link looks like between frames
    input  logic        terminate,      // High on the end of the current frame
    input  logic        error,          // High when PCS decoder encountered an invalid sync header or unrecognized block type

    // Output to async FIFO to 10G-Base-R PCS
    output logic [83:0] PCS_in,         // 84 bit FIFO transport
    output logic        axls_tready
);

    assign axls_tready = mac_tready;

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
        end else if (mac_tready) begin
            data_buffer      <= data;
            ctrl_buffer      <= ctrl;
            keep_buffer      <= keep;
            start_buffer     <= start;
            idle_buffer      <= idle;
            terminate_buffer <= terminate;
            error_buffer     <= error;
        end
    end

    assign PCS_in[63:0]  = data_buffer;
    assign PCS_in[71:64] = ctrl_buffer;
    assign PCS_in[79:72] = keep_buffer;
    assign PCS_in[80]    = start_buffer;
    assign PCS_in[81]    = idle_buffer;
    assign PCS_in[82]    = terminate_buffer;
    assign PCS_in[83]    = error_buffer;

endmodule
`default_nettype wire
