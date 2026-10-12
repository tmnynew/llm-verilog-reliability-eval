module ps2_rx #(parameter TIMEOUT = 200) (
    input clk,
    input rst_n,
    input ps2_clk,
    input ps2_data,
    output reg [7:0] data,
    output reg valid,
    output reg err
);

    // 同步寄存器
    reg ps2_clk_s1, ps2_clk_s2;
    reg ps2_data_s1, ps2_data_s2;
    reg ps2_clk_s3;
    reg ps2_data_s3;

    // 边沿检测
    wire neg_edge;

    // 状态机
    localparam IDLE = 2'd0;
    localparam RECV = 2'd1;
    localparam DONE = 2'd2;

    reg [1:0] state;
    reg [3:0] bit_cnt;
    reg [7:0] shift_reg;
    reg parity;
    reg [15:0] timeout_cnt;
    reg timeout_en;

    // 同步器
    always @(posedge clk) begin
        if (!rst_n) begin
            ps2_clk_s1 <= 1'b1;
            ps2_clk_s2 <= 1'b1;
            ps2_clk_s3 <= 1'b1;
            ps2_data_s1 <= 1'b1;
            ps2_data_s2 <= 1'b1;
            ps2_data_s3 <= 1'b1;
        end else begin
            ps2_clk_s1 <= ps2_clk;
            ps2_clk_s2 <= ps2_clk_s1;
            ps2_clk_s3 <= ps2_clk_s2;
            ps2_data_s1 <= ps2_data;
            ps2_data_s2 <= ps2_data_s1;
            ps2_data_s3 <= ps2_data_s2;
        end
    end

    assign neg_edge = (ps2_clk_s2 == 1'b1) && (ps2_clk_s3 == 1'b0);

    // 超时计数器
    always @(posedge clk) begin
        if (!rst_n) begin
            timeout_cnt <= 16'd0;
        end else if (timeout_en) begin
            if (neg_edge) begin
                timeout_cnt <= 16'd0;
            end else if (timeout_cnt < TIMEOUT) begin
                timeout_cnt <= timeout_cnt + 1'b1;
            end
        end else begin
            timeout_cnt <= 16'd0;
        end
    end

    // 主状态机
    always @(posedge clk) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_cnt <= 4'd0;
            shift_reg <= 8'd0;
            parity <= 1'b0;
            valid <= 1'b0;
            err <= 1'b0;
            timeout_en <= 1'b0;
            data <= 8'd0;
        end else begin
            valid <= 1'b0;
            err <= 1'b0;

            case (state)
                IDLE: begin
                    if (neg_edge && ps2_data_s3 == 1'b0) begin
                        state <= RECV;
                        bit_cnt <= 4'd0;
                        shift_reg <= 8'd0;
                        parity <= 1'b0;
                        timeout_en <= 1'b1;
                    end
                end

                RECV: begin
                    if (timeout_cnt >= TIMEOUT) begin
                        state <= IDLE;
                        timeout_en <= 1'b0;
                    end else if (neg_edge) begin
                        if (bit_cnt < 4'd8) begin
                            shift_reg[bit_cnt] <= ps2_data_s3;
                            parity <= parity ^ ps2_data_s3;
                            bit_cnt <= bit_cnt + 1'b1;
                        end else if (bit_cnt == 4'd8) begin
                            parity <= parity ^ ps2_data_s3;
                            bit_cnt <= bit_cnt + 1'b1;
                        end else if (bit_cnt == 4'd9) begin
                            // 停止位
                            if (ps2_data_s3 == 1'b1 && parity == 1'b1) begin
                                data <= shift_reg;
                                valid <= 1'b1;
                            end else begin
                                err <= 1'b1;
                            end
                            state <= IDLE;
                            timeout_en <= 1'b0;
                        end
                    end
                end

                default: begin
                    state <= IDLE;
                    timeout_en <= 1'b0;
                end
            endcase
        end
    end

endmodule
