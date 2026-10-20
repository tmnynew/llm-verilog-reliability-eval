module pulse_stretch #(parameter LEN = 8) (
    input clk,
    input rst_n,
    input in,
    output out
);
    reg [3:0] counter;
    reg out_reg;
    
    assign out = out_reg;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 4'b0;
            out_reg <= 1'b0;
        end
        else begin
            if (in || (counter > 0)) begin
                if (counter == (LEN - 1)) begin
                    counter <= 4'b0;
                    out_reg <= 1'b0;
                end
                else begin
                    counter <= counter + 1'b1;
                    out_reg <= 1'b1;
                end
            end
            else begin
                counter <= 4'b0;
                out_reg <= 1'b0;
            end
        end
    end
endmodule
