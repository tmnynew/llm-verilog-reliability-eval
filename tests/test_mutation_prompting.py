import json

from vleval.models import SpecVersion, Strategy
from vleval.mutation import _candidates, generate_mutants, tokenize
from vleval.prompting import PromptBuilder

SEQ = """
module c (input clk, input rst_n, input en, output reg [3:0] q);
    localparam LAST = 4'd9;
    always @(posedge clk) begin
        if (!rst_n)
            q <= 4'd0;
        else if (en) begin
            q <= q + 1'b1;
            if (q == LAST) q <= 4'd0;
        end
    end
endmodule
"""

COMB = """
module d (input [1:0] s, output reg y);
    always @(*) begin
        case (s)
            2'b00: y = 1'b0;
            2'b01: y = 1'b1;
            default: y = 1'b0;
        endcase
    end
endmodule
"""


def test_tokenizer_tracks_always_and_param_context():
    toks = tokenize(SEQ)
    nb = [t for t in toks if t.text == "<="]
    assert nb and all(t.in_always and t.in_seq_always for t in nb)
    nine = next(t for t in toks if t.text == "4'd9")
    assert nine.in_param_decl
    comb_eq = [t for t in tokenize(COMB) if t.text == "="]
    assert comb_eq and all(t.in_always and not t.in_seq_always for t in comb_eq)


def test_tokenizer_param_context_covers_comma_lists():
    code = (
        "module v #(parameter H_A = 640, H_S = 96,\n           parameter V_A = 480, V_S = 2) (input clk, output [9:0] x);\n    assign x = H_S + 7;\nendmodule"
    )
    toks = tokenize(code)
    for lit in ("640", "96", "480", "2"):
        assert next(t for t in toks if t.text == lit).in_param_decl
    seven = next(t for t in toks if t.text == "7")
    assert not seven.in_param_decl


def test_for_loop_header_is_never_mutated():
    code = (
        "module r (input clk, input rst_n, output [31:0] q);\n"
        "    reg [31:0] rf [0:31]; integer k;\n"
        "    always @(posedge clk) begin\n"
        "        if (!rst_n) begin for (k = 0; k < 32; k = k + 1) rf[k] <= 32'd0; end\n"
        "        else rf[0] <= rf[0] + 32'd1;\n"
        "    end\n"
        "    assign q = rf[0];\nendmodule"
    )
    toks = tokenize(code)
    assert next(t for t in toks if t.text == "32" and t.kind != "op").in_for_header
    header_ops = [t for t in toks if t.in_for_header and t.text in ("<", "+")]
    assert header_ops
    cands = _candidates(code)
    assert not any(c[1] <= t.start < c[2] for c in cands for t in header_ops)
    assert any(c[3] == "+" for c in cands)  # the `+ 32'd1` in the body is still mutated


def test_candidate_families():
    ops = {c[0] for c in _candidates(SEQ)}
    assert {"ROR", "AOR", "RST", "UOI", "CRP", "BSR"} <= ops
    # parameter declaration must not be mutated
    assert not any(c[3] == "4'd9" for c in _candidates(SEQ))
    # blocking swap only where the register is read later in the same block
    bsr = [c for c in _candidates(SEQ) if c[0] == "BSR"]
    assert len(bsr) == 1  # `q <= q + 1` is followed by `if (q == LAST)`
    comb_ops = {c[0] for c in _candidates(COMB)}
    assert "BSR" not in comb_ops and "DDL" in comb_ops and "CRP" in comb_ops


def test_generate_mutants_is_deterministic_and_single_change():
    a = generate_mutants(SEQ, n=8, seed=3)
    b = generate_mutants(SEQ, n=8, seed=3)
    assert [m.meta() for m in a] == [m.meta() for m in b]
    assert len(a) <= 8 and len({m.id for m in a}) == len(a)
    for m in a:
        body = m.code.split("\n", 1)[1]  # drop header comment
        assert body != SEQ and body.count(m.replacement) >= 1
        json.dumps(m.meta())  # serialisable


def test_prompt_builder_orthogonality(bench):
    pb = PromptBuilder()
    p = bench.get("counter_param")
    zero = pb.build(p, SpecVersion.DETAILED, Strategy.ZERO_SHOT)
    cons = pb.build(p, SpecVersion.DETAILED, Strategy.CODING_CONSTRAINT)
    brief = pb.build(p, SpecVersion.BRIEF, Strategy.ZERO_SHOT)
    assert zero[0]["role"] == "system" and "Verilog-2001" in zero[0]["content"]
    assert "module counter_param" in zero[1]["content"]
    assert "非阻塞" in cons[1]["content"] and "非阻塞" not in zero[1]["content"]
    assert len(brief[1]["content"]) < len(zero[1]["content"])
    few = pb.build(p, SpecVersion.DETAILED, Strategy.FEW_SHOT)
    assert "示例 1" in few[1]["content"]
    rep = pb.build_repair(p, "module counter_param(); endmodule", "TB_FAIL tag=reset")
    assert rep["role"] == "user" and "TB_FAIL" in rep["content"]


def test_specs_carry_no_coding_style_rules(bench):
    assert bench.validate_static() == []
    assert len(bench) == 30  # 3 levels x 10 problems (paper Sec. 2.1)
