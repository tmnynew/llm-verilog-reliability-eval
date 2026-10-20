module debounce #(parameter STABLE_CYCLES = 16) (
    input clk,
    input rst_n,
    input btn_in,
    output reg btn_out
);

    reg [3:0] counter_width;
    reg [$clog2(STABLE_CYCLES+1)-1:0] count;
    reg btn_in_sync;

    initial begin
        if (STABLE_CYCLES == 0) counter_width = 4'd1;
        else counter_width = $clog2(STABLE_CYCLES + 1);
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_out <= 1'b0;
            btn_in_sync <= 1'b0;
            count <= {($clog2(STABLE_CYCLES+1)){1'b0}};
        end else begin
            btn_in_sync <= btn_in;
            
            if (btn_in_sync != btn_out) begin
                if (count < STABLE_CYCLES) begin
                    count <= count + 1'b1;
                end else begin
                    btn_out <= btn_in_sync;
                    count <= {($clog2(STABLE_CYCLES+1)){1'b0}};
                end
            end else begin
                count <= {($clog2(STABLE_CYCLES+1)){1'b0}};
            end
        end
    end

endmodule
