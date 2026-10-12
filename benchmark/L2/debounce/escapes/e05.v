module debounce #(parameter STABLE_CYCLES = 16) (
    input clk,
    input rst_n,
    input btn_in,
    output btn_out
);
    reg [3:0] counter;
    reg btn_out_reg;
    
    wire input_different = (btn_in != btn_out_reg);
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            btn_out_reg <= 1'b1; // 复位时输出高电平
        end else begin
            if (input_different) begin
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
