module pulse_stretch #(parameter LEN = 8) (
    input clk,
    input rst_n,
    input in,
    output out
);
    parameter CNT_WIDTH = $clog2(LEN + 1);
    
    reg [CNT_WIDTH-1:0] counter;
    reg out_r;
    
    wire timeout = (counter == {CNT_WIDTH{1'b1}}) ? (LEN == (1 << CNT_WIDTH) - 1) : (counter == (LEN - 1));
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            out_r <= 0;
        end else begin
            if (in || (out_r && !timeout)) begin
                counter <= 0;
                out_r <= 1;
            end else if (out_r && timeout) begin
                out_r <= 0;
            end
            
            if (out_r && !timeout) begin
                counter <= counter + 1;
            end
        end
    end
    
    assign out = out_r;
endmodule
