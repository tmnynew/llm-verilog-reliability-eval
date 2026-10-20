// MUTANT m004 WID line 12: '3' -> '2'
// Golden reference: 4-bit comparator with unsigned / two's-complement mode
module comparator4 (
    input  [3:0] a,
    input  [3:0] b,
    input        signed_mode,
    output       gt,
    output       eq,
    output       lt
);
    // Flip the MSB in signed mode: maps two's complement onto an order-preserving unsigned code.
    wire [3:0] ax = {a[3] ^ signed_mode, a[2:0]};
    wire [2:0] bx = {b[3] ^ signed_mode, b[2:0]};

    assign eq = (a == b);
    assign gt = (ax > bx);
    assign lt = (ax < bx);
endmodule
