module ps2_rx #(parameter TIMEOUT = 200) (
    input clk,
    input rst_n,
    input ps2_clk,
    input ps2_data,
    output [7:0] data,
    output valid,
    output err
);

    // Synchronizers
    reg ps2_clk_s1, ps2_clk_s2, ps2_clk_s3;
    reg ps2_data_s1, ps2_data_s2;

    always @(posedge clk) begin
        if (!rst_n) begin
            ps2_clk_s1 <= 1'b1;
            ps2_clk_s2 <= 1'b1;
            ps2_clk_s3 <= 1'b1;
            ps2_data_s1 <= 1'b1;
            ps2_data_s2 <= 1'b1;
        end else begin
            ps2_clk_s1 <= ps2_clk;
            ps2_clk_s2 <= ps2_clk_s1;
            ps2_clk_s3 <= ps2_clk_s2;
            ps2_data_s1 <= ps2_data;
            ps2_data_s2 <= ps2_data_s1;
        end
    end

    wire fall_edge = ps2_clk_s3 & ~ps2_clk_s2;

    // State encoding
    localparam S_IDLE  = 4'd0;
    localparam S_D0    = 4'd1;
    localparam S_D1    = 4'd2;
    localparam S_D2    = 4'd3;
    localparam S_D3    = 4'd4;
    localparam S_D4    = 4'd5;
    localparam S_D5    = 4'd6;
    localparam S_D6    = 4'd7;
    localparam S_D7    = 4'd8;
    localparam S_PAR   = 4'd9;
    localparam S_STOP  = 4'd10;
    localparam S_DONE  = 4'd11;

    reg [3:0] state, state_n;
    reg [7:0] shift;
    reg par;
    reg [31:0] timer;

    always @(posedge clk) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= state_n;
    end

    // Next-state logic
    always @(*) begin
        state_n = state;
        case (state)
            S_IDLE:  if (fall_edge && !ps2_data_s2) state_n = S_D0;
            S_D0:    if (fall_edge) state_n = S_D1;
            S_D1:    if (fall_edge) state_n = S_D2;
            S_D2:    if (fall_edge) state_n = S_D3;
            S_D3:    if (fall_edge) state_n = S_D4;
            S_D4:    if (fall_edge) state_n = S_D5;
            S_D5:    if (fall_edge) state_n = S_D6;
            S_D6:    if (fall_edge) state_n = S_D7;
            S_D7:    if (fall_edge) state_n = S_PAR;
            S_PAR:   if (fall_edge) state_n = S_STOP;
            S_STOP:  if (fall_edge) state_n = S_DONE;
            S_DONE:  state_n = S_IDLE;
            default: state_n = S_IDLE;
        endcase
    end

    // Timer
    always @(posedge clk) begin
        if (!rst_n) begin
            timer <= 32'd0;
        end else begin
            if (state == S_IDLE)
                timer <= 32'd0;
            else if (fall_edge)
                timer <= 32'd0;
            else if (state != S_DONE)
                timer <= timer + 32'd1;
        end
    end

    // Shift register
    always @(posedge clk) begin
        if (!rst_n) begin
            shift <= 8'd0;
            par   <= 1'b0;
        end else begin
            if (fall_edge) begin
                case (state)
                    S_D0:    shift[0] <= ps2_data_s2;
                    S_D1:    shift[1] <= ps2_data_s2;
                    S_D2:    shift[2] <= ps2_data_s2;
                    S_D3:    shift[3] <= ps2_data_s2;
                    S_D4:    shift[4] <= ps2_data_s2;
                    S_D5:    shift[5] <= ps2_data_s2;
                    S_D6:    shift[6] <= ps2_data_s2;
                    S_D7:    shift[7] <= ps2_data_s2;
                    S_PAR:   par     <= ps2_data_s2;
                    default: ;
                endcase
            end
        end
    end

    // Timeout
    wire timeout = (timer >= TIMEOUT);

    // Output logic
    reg valid_r, err_r;
    reg [7:0] data_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            valid_r <= 1'b0;
            err_r   <= 1'b0;
            data_r  <= 8'd0;
        end else begin
            valid_r <= 1'b0;
            err_r   <= 1'b0;
            if (state == S_DONE) begin
                if (ps2_data_s2 && (^{shift, par}))
                    data_r  <= shift;
                else
                    err_r   <= 1'b1;
                if (ps2_data_s2 && (^{shift, par}))
                    valid_r <= 1'b1;
            end else if ((state != S_IDLE) && (state != S_DONE) && timeout) begin
                // Silent abort
            end
        end
    end

    assign data  = data_r;
    assign valid = valid_r;
    assign err   = err_r;

endmodule
