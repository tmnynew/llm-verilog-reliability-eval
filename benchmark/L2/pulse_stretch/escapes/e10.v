module pulse_stretch #(parameter LEN = 8) (
    input clk,
    input rst_n,
    input in,
    output reg out
);

    reg [3:0] counter;
    reg counter_en;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter <= 0;
            counter_en <= 0;
            out <= 0;
        end else begin
            if (in) begin
                counter <= LEN - 1;
                counter_en <= 1;
                out <= 1;
            end else if (counter_en && counter > 0) begin
                counter <= counter - 1;
                if (counter == 1) begin
                    counter_en <= 0;
                    out <= 0;
                end
            end
        end
    end

endmodule
