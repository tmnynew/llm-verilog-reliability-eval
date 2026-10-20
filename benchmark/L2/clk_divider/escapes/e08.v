module clk_divider (
    input clk,
    input rst_n,
    input [7:0] div,
    output reg tick,
    output reg clk_out
);

    reg [7:0] counter;
    reg [7:0] half_div;
    reg tick_next;
    
    always @(posedge clk) begin
        if (!rst_n) begin
            counter <= 8'b0;
            tick <= 1'b0;
            clk_out <= 1'b0;
            half_div <= 8'b0;
        end else begin
            // Update half_div when div changes
            half_div <= div >> 1;
            
            // Counting logic
            if (counter >= div - 1) begin
                counter <= 8'b0;
                tick <= 1'b1;
            end else begin
                counter <= counter + 1;
                tick <= 1'b0;
            end
            
            // clk_out generation
            if (counter < half_div) begin
                clk_out <= 1'b1;
            end else begin
                clk_out <= 1'b0;
            end
        end
    end

endmodule
