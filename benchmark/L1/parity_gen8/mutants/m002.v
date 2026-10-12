// MUTANT m002 LOR line 7: '^' -> '|'
// Golden reference: 8-bit parity generator (odd = 1 selects odd parity)
module parity_gen8 (
    input  [7:0] data,
    input        odd,
    output       parity
);
    assign parity = (^data) | odd;
endmodule
