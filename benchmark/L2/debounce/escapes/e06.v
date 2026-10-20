module debounce #(parameter STABLE_CYCLES = 16) (
    input clk,
    input rst_n,
    input btn_in,
    output btn_out
);

    reg [31:0] count;
    reg current_state, next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            current_state <= 0;
        end else begin
            if (btn_in == current_state) begin
                count <= 0;
            end else begin
                count <= count + 1;
                if (count == STABLE_CYCLES - 1) begin
                    current_state <= btn_in;
                end
            end
        end
    end

    assign btn_out = current_state;

endmodule
