module debounce #(parameter STABLE_CYCLES = 16) (
    input clk,
    input rst_n,
    input btn_in,
    output btn_out
);

reg [31:0] counter;
reg current_btn_out;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        counter <= 0;
        current_btn_out <= 0;
    end else begin
        if (btn_in == current_btn_out) begin
            counter <= 0;
        end else begin
            counter <= counter + 1;
            if (counter == STABLE_CYCLES - 1) begin
                current_btn_out <= btn_in;
            end
        end
    end
end

assign btn_out = current_btn_out;

endmodule
