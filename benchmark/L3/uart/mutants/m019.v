// MUTANT m019 CRP line 117: "1'b1" -> "1'b0"
// Golden reference: 8N1 UART transceiver, CLKS_PER_BIT clocks per bit, synchronous active-low reset
module uart #(
    parameter CLKS_PER_BIT = 16
) (
    input        clk,
    input        rst_n,
    // transmitter
    input        tx_start,
    input  [7:0] tx_data,
    output reg   tx_busy,
    output reg   tx,
    // receiver
    input        rx,
    output reg [7:0] rx_data,
    output reg   rx_valid,
    output reg   rx_err
);
    // ------------------------------------------------------------------ //
    // Transmitter
    // ------------------------------------------------------------------ //
    reg [9:0]  tx_shift;     // {stop, data[7:0], start}
    reg [3:0]  tx_bit_idx;   // 0..9
    reg [15:0] tx_clk_cnt;

    always @(posedge clk) begin
        if (!rst_n) begin
            tx         <= 1'b1;
            tx_busy    <= 1'b0;
            tx_shift   <= 10'h3FF;
            tx_bit_idx <= 4'd0;
            tx_clk_cnt <= 16'd0;
        end else if (!tx_busy) begin
            tx <= 1'b1;
            if (tx_start) begin
                tx_busy    <= 1'b1;
                tx_shift   <= {1'b1, tx_data, 1'b0};
                tx_bit_idx <= 4'd0;
                tx_clk_cnt <= 16'd0;
                tx         <= 1'b0;              // start bit begins immediately
            end
        end else begin
            if (tx_clk_cnt == CLKS_PER_BIT - 1) begin
                tx_clk_cnt <= 16'd0;
                if (tx_bit_idx == 4'd9) begin
                    tx_busy <= 1'b0;             // stop bit finished
                    tx      <= 1'b1;
                end else begin
                    tx_bit_idx <= tx_bit_idx + 1'b1;
                    tx         <= tx_shift[tx_bit_idx + 1];
                end
            end else begin
                tx_clk_cnt <= tx_clk_cnt + 1'b1;
            end
        end
    end

    // ------------------------------------------------------------------ //
    // Receiver
    // ------------------------------------------------------------------ //
    localparam RX_IDLE  = 2'd0,
               RX_START = 2'd1,
               RX_DATA  = 2'd2,
               RX_STOP  = 2'd3;

    reg [1:0]  rx_state;
    reg [15:0] rx_clk_cnt;
    reg [2:0]  rx_bit_idx;
    reg [7:0]  rx_shift;

    always @(posedge clk) begin
        if (!rst_n) begin
            rx_state   <= RX_IDLE;
            rx_clk_cnt <= 16'd0;
            rx_bit_idx <= 3'd0;
            rx_shift   <= 8'd0;
            rx_data    <= 8'd0;
            rx_valid   <= 1'b0;
            rx_err     <= 1'b0;
        end else begin
            rx_valid <= 1'b0;
            rx_err   <= 1'b0;
            case (rx_state)
                RX_IDLE: begin
                    rx_clk_cnt <= 16'd0;
                    rx_bit_idx <= 3'd0;
                    if (rx == 1'b0)
                        rx_state <= RX_START;
                end
                RX_START: begin                       // wait for the middle of the start bit
                    if (rx_clk_cnt == (CLKS_PER_BIT / 2) - 1) begin
                        rx_clk_cnt <= 16'd0;
                        rx_state   <= (rx == 1'b0) ? RX_DATA : RX_IDLE;   // glitch filter
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end
                RX_DATA: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt           <= 16'd0;
                        rx_shift[rx_bit_idx] <= rx;
                        if (rx_bit_idx == 3'd7)
                            rx_state <= RX_STOP;
                        else
                            rx_bit_idx <= rx_bit_idx + 1'b1;
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (rx_clk_cnt == CLKS_PER_BIT - 1) begin
                        rx_clk_cnt <= 16'd0;
                        rx_state   <= RX_IDLE;
                        if (rx == 1'b1) begin
                            rx_data  <= rx_shift;
                            rx_valid <= 1'b1;
                        end else begin
                            rx_err <= 1'b0;
                        end
                    end else begin
                        rx_clk_cnt <= rx_clk_cnt + 1'b1;
                    end
                end
                default: rx_state <= RX_IDLE;
            endcase
        end
    end
endmodule
