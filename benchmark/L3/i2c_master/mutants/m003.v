// MUTANT m003 AOR line 29: '-' -> '+'
// Golden reference: single-byte I2C master with 4-phase bit timing
module i2c_master #(
    parameter CLK_DIV = 4
) (
    input            clk,
    input            rst_n,
    input            start,
    input            rw,
    input      [6:0] addr,
    input      [7:0] wdata,
    output reg [7:0] rdata,
    output           busy,
    output reg       done,
    output reg       ack_err,
    output reg       scl_o,
    output reg       sda_o,
    input            sda_i
);
    localparam S_IDLE = 4'd0, S_START = 4'd1, S_ADDR = 4'd2, S_ACKA = 4'd3, S_WDATA = 4'd4,
               S_ACKW = 4'd5, S_RDATA = 4'd6, S_NACK = 4'd7, S_STOP = 4'd8;

    reg [3:0]  state;
    reg [1:0]  phase;
    reg [15:0] div_cnt;
    reg [2:0]  bit_cnt;
    reg [7:0]  sh, rsh, wdata_r;
    reg        rw_r;

    wire tick = (div_cnt == CLK_DIV + 1);
    assign busy = (state != S_IDLE);

    always @(posedge clk) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            phase   <= 2'd0;
            div_cnt <= 16'd0;
            scl_o   <= 1'b1;
            sda_o   <= 1'b1;
            done    <= 1'b0;
            ack_err <= 1'b0;
            rdata   <= 8'd0;
            bit_cnt <= 3'd0;
            sh      <= 8'd0;
            rsh     <= 8'd0;
            wdata_r <= 8'd0;
            rw_r    <= 1'b0;
        end else begin
            done <= 1'b0;
            if (state == S_IDLE) begin
                scl_o   <= 1'b1;
                sda_o   <= 1'b1;
                div_cnt <= 16'd0;
                phase   <= 2'd0;
                if (start) begin
                    state   <= S_START;
                    sh      <= {addr, rw};
                    rw_r    <= rw;
                    wdata_r <= wdata;
                    ack_err <= 1'b0;
                end
            end else if (!tick) begin
                div_cnt <= div_cnt + 16'd1;
            end else begin
                div_cnt <= 16'd0;
                phase   <= phase + 2'd1;
                case (state)
                    S_START: case (phase)
                        2'd1: sda_o <= 1'b0;
                        2'd2: scl_o <= 1'b0;
                        2'd3: begin state <= S_ADDR; bit_cnt <= 3'd7; end
                        default: ;
                    endcase
                    S_ADDR, S_WDATA, S_NACK: case (phase)
                        2'd0: sda_o <= (state == S_NACK) ? 1'b1 : sh[bit_cnt];
                        2'd1: scl_o <= 1'b1;
                        2'd3: begin
                            scl_o <= 1'b0;
                            if (state == S_NACK)      state <= S_STOP;
                            else if (bit_cnt == 3'd0) state <= (state == S_ADDR) ? S_ACKA : S_ACKW;
                            else                      bit_cnt <= bit_cnt - 3'd1;
                        end
                        default: ;
                    endcase
                    S_ACKA, S_ACKW, S_RDATA: case (phase)
                        2'd0: sda_o <= 1'b1;
                        2'd1: scl_o <= 1'b1;
                        2'd2: if (state == S_RDATA) rsh[bit_cnt] <= sda_i; else ack_err <= sda_i;
                        2'd3: begin
                            scl_o <= 1'b0;
                            case (state)
                                S_ACKA: if (ack_err)   state <= S_STOP;
                                        else if (rw_r) begin state <= S_RDATA; bit_cnt <= 3'd7; end
                                        else           begin state <= S_WDATA; sh <= wdata_r; bit_cnt <= 3'd7; end
                                S_ACKW: state <= S_STOP;
                                default: if (bit_cnt == 3'd0) begin state <= S_NACK; rdata <= rsh; end
                                         else bit_cnt <= bit_cnt - 3'd1;
                            endcase
                        end
                    endcase
                    S_STOP: case (phase)
                        2'd0: sda_o <= 1'b0;
                        2'd1: scl_o <= 1'b1;
                        2'd2: sda_o <= 1'b1;
                        2'd3: begin state <= S_IDLE; done <= 1'b1; end
                    endcase
                    default: state <= S_IDLE;
                endcase
            end
        end
    end
endmodule
