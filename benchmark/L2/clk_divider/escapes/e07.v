module clk_divider (
    input clk,
    input rst_n,
    input [7:0] div,
    output reg tick,
    output reg clk_out
);

    reg [7:0] counter;
    reg [7:0] half_div;
    reg prev_counter_max;

    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 8'b0;
            tick <= 1'b0;
            clk_out <= 1'b0;
            half_div <= 8'b0;
            prev_counter_max <= 1'b0;
        end else begin
            // Calculate half_div for clk_out generation
            half_div <= div >> 1;
            
            // Check if we're about to reach max and wrap around
            if (counter >= (div - 1)) begin
                counter <= 8'b0;
                prev_counter_max <= 1'b1;
            end else begin
                counter <= counter + 1;
                prev_counter_max <= 1'b0;
            end
            
            // Generate tick when wrapping around
            tick <= prev_counter_max;
            
            // Generate clk_out based on counter value
            if (counter < half_div) begin
                clk_out <= 1'b1;
            end else begin
                clk_out <= 1'b0;
            end
        end
    end

endmodule
