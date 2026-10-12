from vleval.extract import (
    check_interface,
    effective_lines,
    extract_code,
    parse_module,
    sim_only_constructs,
    systemverilog_constructs,
)
from vleval.models import Interface, Port

IFACE = Interface("priority_encoder8", [Port("in", "input", 8), Port("idx", "output", 3), Port("valid", "output", 1)])

GOOD = """
module priority_encoder8 (
    input  [7:0] in,
    output reg [2:0] idx,
    output       valid
);
    assign valid = |in;
    always @(*) idx = 0;
endmodule
"""


def test_extract_prefers_fenced_block_with_module():
    resp = "Here you go:\n```verilog\n" + GOOD + "```\nSome notes.\n```python\nprint(1)\n```"
    assert extract_code(resp).strip() == GOOD.strip()


def test_extract_falls_back_to_raw_text():
    assert "endmodule" in extract_code(GOOD)


def test_parse_module_ansi_and_non_ansi():
    m = parse_module(GOOD)
    assert m.name == "priority_encoder8"
    assert {p.name: p.width for p in m.ports} == {"in": 8, "idx": 3, "valid": 1}
    non_ansi = "module foo(a, b); input [3:0] a; output b; endmodule"
    m2 = parse_module(non_ansi)
    assert [(p.name, p.direction, p.width) for p in m2.ports] == [("a", "input", 4), ("b", "output", 1)]


def test_parse_module_parameterised_width():
    code = "module c #(parameter WIDTH = 8) (input clk, output [WIDTH-1:0] count); endmodule"
    m = parse_module(code)
    assert m.parameters == {"WIDTH": "8"}
    assert m.ports[1].width == 8


def test_parse_module_comma_separated_parameters():
    code = "module v #(parameter H_A = 640, H_S = 96,\n           parameter V_A = 480, V_S = 2) (input clk, output [$clog2(H_A)-1:0] x); endmodule"
    m = parse_module(code)
    assert m.parameters == {"H_A": "640", "H_S": "96", "V_A": "480", "V_S": "2"}


def test_check_interface_reports_all_issues():
    ok, issues = check_interface(GOOD, IFACE)
    assert ok and issues == []
    bad = GOOD.replace("[7:0] in", "[6:0] in").replace("output       valid", "output       vld")
    ok, issues = check_interface(bad, IFACE)
    assert not ok
    assert any("width" in i for i in issues)
    assert any("missing port valid" in i for i in issues)
    assert any("unexpected port vld" in i for i in issues)


def test_check_interface_missing_parameter():
    iface = Interface("c", [Port("clk", "input")], parameters={"WIDTH": 8})
    ok, issues = check_interface("module c (input clk); endmodule", iface)
    assert not ok and "missing parameter WIDTH" in issues


def test_effective_lines_ignores_comments_and_blanks():
    code = "// c\n/* block\n */\nmodule a;\n\n  wire x; // trailing\nendmodule\n"
    assert effective_lines(code) == 3


def test_static_hints():
    code = "module a; initial begin #5 x = 1; end always_ff @(posedge c) q <= d; logic z; endmodule"
    assert sim_only_constructs(code) == {"initial": 1, "delay": 1}
    sv = systemverilog_constructs(code)
    assert sv["logic"] == 1 and sv["always_ff"] == 1
