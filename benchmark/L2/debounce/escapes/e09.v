module debounce #(parameter STABLE_CYCLES = 16) (
    input clk,
    input rst_n,
    input btn_in,
    output btn_out
);

    reg [31:0] count;
    reg btn_out_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            btn_out_reg <= 0;
        end else begin
            if (btn_in == btn_out_reg) begin
                count <= 0;
            end else begin
                count <= count + 1;
                if (count == STABLE_CYCLES - 1) begin
                    btn_out_reg <= btn_in;
                end
            end
        end
    end
    
    assign btn_out = btn_out_reg;

endmodule
