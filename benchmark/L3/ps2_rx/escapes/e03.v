module ps2_rx #(parameter TIMEOUT = 200) (
    input clk,
    input rst_n,
    input ps2_clk,
    input ps2_data,
    output [7:0] data,
    output valid,
    output err
);

    reg [3:0] bit_cnt;
    reg [9:0] timeout_cnt; // log2(200) < 10 bits
    reg [7:0] rx_data;
    reg [8:0] parity_gen; // for parity calculation
    reg state_idle, state_receiving, state_counting;
    reg ps2_clk_d, ps2_clk_dd;
    reg ps2_data_d, ps2_data_dd;
    reg valid_r, err_r;
    
    wire ps2_clk_negedge = ~ps2_clk_dd & ps2_clk_d;
    wire timeout_reached = (timeout_cnt >= TIMEOUT-1);
    
    assign data = rx_data;
    assign valid = valid_r;
    assign err = err_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ps2_clk_d <= 1'b1;
            ps2_clk_dd <= 1'b1;
            ps2_data_d <= 1'b1;
            ps2_data_dd <= 1'b1;
        end else begin
            ps2_clk_d <= ps2_clk;
            ps2_clk_dd <= ps2_clk_d;
            ps2_data_d <= ps2_data;
            ps2_data_dd <= ps2_data_d;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_idle <= 1'b1;
            state_receiving <= 1'b0;
            state_counting <= 1'b0;
            bit_cnt <= 4'h0;
            timeout_cnt <= 10'h0;
            rx_data <= 8'h0;
            parity_gen <= 9'h0;
            valid_r <= 1'b0;
            err_r <= 1'b0;
        end else begin
            valid_r <= 1'b0;
            err_r <= 1'b0;
            
            case ({state_idle, state_receiving, state_counting})
                3'b100: begin // IDLE
                    if (ps2_clk_negedge && !ps2_data_dd) begin // start bit is 0
                        state_idle <= 1'b0;
                        state_receiving <= 1'b1;
                        state_counting <= 1'b0;
                        bit_cnt <= 4'h0;
                        timeout_cnt <= 10'h0;
                        rx_data <= 8'h0;
                        parity_gen <= 9'h0;
                    end
                end
                
                3'b010: begin // RECEIVING
                    if (ps2_clk_negedge) begin
                        if (bit_cnt < 4'd8) begin // data bits (LSB first)
                            rx_data <= {ps2_data_dd, rx_data[7:1]};
                            parity_gen <= parity_gen + ps2_data_dd;
                        end else if (bit_cnt == 4'd8) begin // parity bit
                            parity_gen <= parity_gen + ps2_data_dd;
                        end else if (bit_cnt == 4'd9) begin // stop bit
                            // Check parity and stop bit
                            if (parity_gen[0] && ps2_data_dd) begin // odd parity correct and stop bit is 1
                                valid_r <= 1'b1;
                            end else begin
                                err_r <= 1'b1;
                            end
                            
                            state_idle <= 1'b1;
                            state_receiving <= 1'b0;
                            state_counting <= 1'b0;
                        end
                        
                        bit_cnt <= bit_cnt + 1'b1;
                        timeout_cnt <= 10'h0;
                    end else begin
                        timeout_cnt <= timeout_cnt + 1'b1;
                        if (timeout_reached) begin
                            state_idle <= 1'b1;
                            state_receiving <= 1'b0;
                            state_counting <= 1'b0;
                            err_r <= 1'b1;
                        end
                    end
                end
                
                3'b001: begin // COUNTING (should not happen in this design)
                    state_idle <= 1'b1;
                    state_receiving <= 1'b0;
                    state_counting <= 1'b0;
                    timeout_cnt <= 10'h0;
                end
                
                default: begin
                    state_idle <= 1'b1;
                    state_receiving <= 1'b0;
                    state_counting <= 1'b0;
                end
            endcase
        end
    end

endmodule
