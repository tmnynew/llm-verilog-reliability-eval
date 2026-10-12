// MUTANT m004 URO line 33: '~' -> ''
// Golden reference: AXI4-Lite slave with 3 RW registers and one read-only ID register
module axi_lite_slave (
    input             clk,
    input             rst_n,
    input             awvalid,
    input      [7:0]  awaddr,
    output            awready,
    input             wvalid,
    input      [31:0] wdata,
    input      [3:0]  wstrb,
    output            wready,
    output reg        bvalid,
    output reg [1:0]  bresp,
    input             bready,
    input             arvalid,
    input      [7:0]  araddr,
    output            arready,
    output reg        rvalid,
    output reg [31:0] rdata,
    output reg [1:0]  rresp,
    input             rready
);
    localparam [31:0] ID     = 32'h5A5A_0003;
    localparam [1:0]  OKAY   = 2'b00, SLVERR = 2'b10, DECERR = 2'b11;

    reg [31:0] reg0, reg1, reg2;
    reg        aw_got, w_got;
    reg [7:0]  awaddr_r;
    reg [31:0] wdata_r;
    reg [3:0]  wstrb_r;

    assign awready = ~aw_got & ~bvalid;
    assign wready  = ~w_got & bvalid;
    assign arready = ~rvalid;

    wire [31:0] wmask = {{8{wstrb_r[3]}}, {8{wstrb_r[2]}}, {8{wstrb_r[1]}}, {8{wstrb_r[0]}}};

    // ---------------- write ----------------
    always @(posedge clk) begin
        if (!rst_n) begin
            aw_got   <= 1'b0;
            w_got    <= 1'b0;
            bvalid   <= 1'b0;
            bresp    <= OKAY;
            awaddr_r <= 8'd0;
            wdata_r  <= 32'd0;
            wstrb_r  <= 4'd0;
            reg0     <= 32'd0;
            reg1     <= 32'd0;
            reg2     <= 32'd0;
        end else begin
            if (awvalid && awready) begin
                aw_got   <= 1'b1;
                awaddr_r <= awaddr;
            end
            if (wvalid && wready) begin
                w_got   <= 1'b1;
                wdata_r <= wdata;
                wstrb_r <= wstrb;
            end
            if (bvalid && bready)
                bvalid <= 1'b0;
            if (aw_got && w_got && !bvalid) begin
                aw_got <= 1'b0;
                w_got  <= 1'b0;
                bvalid <= 1'b1;
                if (awaddr_r[7:4] != 4'd0) begin
                    bresp <= DECERR;
                end else begin
                    bresp <= OKAY;
                    case (awaddr_r[3:2])
                        2'd0: reg0 <= (reg0 & ~wmask) | (wdata_r & wmask);
                        2'd1: reg1 <= (reg1 & ~wmask) | (wdata_r & wmask);
                        2'd2: reg2 <= (reg2 & ~wmask) | (wdata_r & wmask);
                        default: bresp <= SLVERR;
                    endcase
                end
            end
        end
    end

    // ---------------- read ----------------
    always @(posedge clk) begin
        if (!rst_n) begin
            rvalid <= 1'b0;
            rdata  <= 32'd0;
            rresp  <= OKAY;
        end else if (rvalid && rready) begin
            rvalid <= 1'b0;
        end else if (arvalid && arready) begin
            rvalid <= 1'b1;
            if (araddr[7:4] != 4'd0) begin
                rdata <= 32'd0;
                rresp <= DECERR;
            end else begin
                rresp <= OKAY;
                case (araddr[3:2])
                    2'd0: rdata <= reg0;
                    2'd1: rdata <= reg1;
                    2'd2: rdata <= reg2;
                    default: rdata <= ID;
                endcase
            end
        end
    end
endmodule
