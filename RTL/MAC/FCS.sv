module MAC_FCS(
    input logic clk, rst_n,

    input logic [63:0] data,
    input logic [7:0] keep, 
    input logic valid,
    input logic last,
    input logic err,

    input logic tready,
    output logic tvalid, tlast, tuser,
    output logic [7:0] tkeep,
    output logic [63:0] tdata
);

    // buffer previous beat for FCS check
    logic [63:0] prev_data_q;
    logic [7:0] prev_keep_q;
    logic prev_valid_q;
    logic prev_last_q;
    logic prev_user_q;

    // register for AXI Stream
    logic [63:0] tdata_q;
    logic [7:0] tkeep_q;
    logic tvalid_q;
    logic tlast_q;
    logic tuser_q;


    always_ff @(posedge clk) begin
        if (!rst_n) begin
            prev_data_q <= '0;
            prev_keep_q <= '0;
            prev_valid_q <= '0;
            prev_last_q <= '0;
            prev_user_q <= '0;
 
            tdata_q <= '0;
            tkeep_q <= '0;
            tvalid_q <= '0;
            tlast_q <= '0;
            tuser_q <= '0;
        end else if(!tvalid_q  || tready) begin

            if(prev_last_q && prev_valid_q) begin
                tdata_q <= prev_data_q;
                tkeep_q <= prev_keep_q;
                tlast_q <= prev_last_q;
                tvalid_q <= prev_valid_q;
                tuser_q <= prev_user_q;

                prev_last_q <= 1'b0;
                if (valid) begin
                    prev_data_q <= data;
                    prev_keep_q <= keep;
                    prev_last_q <= last;
                    prev_valid_q <= 1'b1;
                    prev_user_q <= err;
                end else begin
                    prev_valid_q <= 1'b0;
                end
            end else if (!prev_valid_q) begin
                tvalid_q <= 1'b0;
                tlast_q  <= 1'b0;
                tuser_q  <= 1'b0;
                if (valid) begin
                    prev_data_q <= data;
                    prev_keep_q <= keep;
                    prev_valid_q <= 1'b1;
                    prev_user_q <= err;
                    prev_last_q <= last;
                end
            end else if (!valid) begin
                tdata_q <= '0;
                tkeep_q <= '0;
                tvalid_q <= '0;
                tlast_q <= '0;
                tuser_q <= '0;
            end else if (!last) begin
                tdata_q <= prev_data_q;
                tkeep_q <= prev_keep_q;
                tvalid_q <= prev_valid_q;
                tlast_q <= prev_last_q;
                tuser_q <= prev_user_q;

                prev_data_q <= data;
                prev_keep_q <= keep;
                prev_valid_q <= valid;
                prev_last_q <= last;
                prev_user_q <= err;
            end else begin
                // last valid beat
                case(keep)
                    8'b0000_0001: begin
                        tdata_q <= prev_data_q; // prev beat has 3 FCS bytes
                        tkeep_q <= 8'b0001_1111;
                        tlast_q <= 1'b1;
                        tvalid_q <= 1'b1;
                        tuser_q <= err;
                        prev_valid_q <= 1'b0;
                    end 
                    8'b0000_0011: begin
                        tdata_q <= prev_data_q; // prev beat has 2 FCS bytes
                        tkeep_q <= 8'b0011_1111;
                        tlast_q <= 1'b1;
                        tvalid_q <= 1'b1;
                        tuser_q <= err;
                        prev_valid_q <= 1'b0;
                    end
                    8'b0000_0111: begin
                        tdata_q <= prev_data_q; // prev beat has 1 FCS byte
                        tkeep_q <= 8'b0111_1111;
                        tlast_q <= 1'b1;
                        tvalid_q <= 1'b1;
                        tuser_q <= err;
                        prev_valid_q <= 1'b0;
                    end
                    8'b0000_1111: begin
                        tdata_q <= prev_data_q; // prev beat has no FCS byte
                        tkeep_q <= 8'b1111_1111;
                        tlast_q <= 1'b1;
                        tvalid_q <= 1'b1;
                        tuser_q <= err;
                        prev_valid_q <= 1'b0;
                    end
                    8'b0001_1111: begin
                        tdata_q <= prev_data_q; 
                        tkeep_q <= prev_keep_q;
                        tlast_q <= 1'b0;
                        tvalid_q <= 1'b1;
                        tuser_q <= 1'b0;

                        prev_valid_q <= 1'b1;
                        prev_keep_q <= 8'b0000_0001; // prev has 1 data byte
                        prev_data_q <= data;
                        prev_last_q <= 1'b1;
                        prev_user_q <= err;
                    end
                    8'b0011_1111: begin
                        tdata_q <= prev_data_q; 
                        tkeep_q <= prev_keep_q;
                        tlast_q <= 1'b0;
                        tvalid_q <= 1'b1;
                        tuser_q <= 1'b0;

                        prev_valid_q <= 1'b1;
                        prev_keep_q <= 8'b0000_0011; // prev has 2 data bytes
                        prev_data_q <= data;
                        prev_last_q <= 1'b1;
                        prev_user_q <= err;
                    end
                    8'b0111_1111: begin
                        tdata_q <= prev_data_q; 
                        tkeep_q <= prev_keep_q;
                        tlast_q <= 1'b0;
                        tvalid_q <= 1'b1;
                        tuser_q <= 1'b0;

                        prev_valid_q <= 1'b1;
                        prev_keep_q <= 8'b0000_0111; // prev has 3 data bytes
                        prev_data_q <= data;
                        prev_last_q <= 1'b1;
                        prev_user_q <= err;
                    end
                    8'b1111_1111: begin
                        tdata_q <= prev_data_q; 
                        tkeep_q <= prev_keep_q;
                        tlast_q <= 1'b0;
                        tvalid_q <= 1'b1;
                        tuser_q <= 1'b0;

                        prev_valid_q <= 1'b1;
                        prev_keep_q <= 8'b0000_1111; // prev has 4 data bytes
                        prev_data_q <= data;
                        prev_last_q <= 1'b1;
                        prev_user_q <= err;
                    end
                    default: begin
                        tvalid_q <= '0;
                        prev_valid_q <= '0;
                    end
                endcase
            end
        end
    end

        assign tdata = tdata_q;
        assign tkeep = tkeep_q;
        assign tvalid = tvalid_q;
        assign tlast = tlast_q;
        assign tuser = tuser_q;

endmodule
