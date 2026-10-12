module debounce #(parameter STABLE_CYCLES = 16) (
    input clk,
    input rst_n,
    input btn_in,
    output btn_out
);
    reg [4:0] counter; // ceil(log2(16)) = 4 bits, use 5 bits for safety
    reg btn_out_reg;
    
    wire different = (btn_in != btn_out_reg);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            btn_out_reg <= 1'b1; // reset to high
        end else begin
            if (different) begin
                if (counter == STABLE_CYCLES - 1) begin
                    btn_out_reg <= btn_in;
                    counter <= 0;
                end else begin
                    counter <= counter + 1;
                end
            end else begin
                counter <= 0;
            end
        end
    end
    
    assign btn_out = btn_out_reg;
endmodule
