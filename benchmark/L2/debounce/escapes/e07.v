module debounce #(parameter STABLE_CYCLES = 16) (
    input clk,
    input rst_n,
    input btn_in,
    output btn_out
);
    reg [4:0] counter_width;
    integer i;
    
    // Calculate counter width
    initial begin
        counter_width = 0;
        for (i = 1; i < STABLE_CYCLES; i = i << 1) begin
            counter_width = counter_width + 1;
        end
    end
    
    reg [4:0] count;
    reg btn_sync1, btn_sync2;
    reg btn_out_r;
    
    always @(*) begin
        if (STABLE_CYCLES == 1) counter_width = 1;
        else counter_width = 5; // For up to 32 cycles with 5 bits
    end
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_sync1 <= 0;
            btn_sync2 <= 0;
            btn_out_r <= 0;
            count <= 0;
        end else begin
            btn_sync1 <= btn_in;
            btn_sync2 <= btn_sync1;
            
            if (btn_sync2 != btn_out_r) begin
                if (count == STABLE_CYCLES - 1) begin
                    btn_out_r <= btn_sync2;
                    count <= 0;
                end else begin
                    count <= count + 1;
                end
            end else begin
                count <= 0;
            end
        end
    end
    
    assign btn_out = btn_out_r;

endmodule
