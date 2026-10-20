// MUTANT m017 LOR line 24: '|' -> '&'
// Golden reference: 4-bit carry-lookahead adder with block P/G outputs
module cla_adder4 (
    input  [3:0] a,
    input  [3:0] b,
    input        cin,
    output [3:0] sum,
    output       cout,
    output       p_out,
    output       g_out
);
    wire [3:0] p = a ^ b;          // bit propagate
    wire [3:0] g = a & b;          // bit generate
    wire [4:0] c;                  // c[0] = cin, c[4] = cout

    assign c[0] = cin;
    assign c[1] = g[0] | (p[0] & c[0]);
    assign c[2] = g[1] | (p[1] & g[0]) | (p[1] & p[0] & c[0]);
    assign c[3] = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0]) | (p[2] & p[1] & p[0] & c[0]);
    assign c[4] = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]) | (p[3] & p[2] & p[1] & p[0] & c[0]);

    assign sum   = p ^ c[3:0];
    assign cout  = c[4];
    assign p_out = &p;
    assign g_out = g[3] | (p[3] & g[2]) & (p[3] & p[2] & g[1]) | (p[3] & p[2] & p[1] & g[0]);
endmodule
