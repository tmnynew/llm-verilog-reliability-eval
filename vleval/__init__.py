"""vleval – reliability evaluation platform for LLM-generated Verilog.

Layers (bottom-up):

    tools/      thin wrappers around Verilator / Icarus / Yosys / Vivado
    extract     code extraction + interface check + static hints
    taxonomy    evidence → E1..E9 classification
    judge       one sample → Verdict (Fig. 2 pipeline)
    llm         OpenAI-compatible client, cache, offline oracle
    prompting   spec × strategy → messages
    runner      generation / repair loop / persistence
    db          SQLite result store
    report      tables + figures for the paper
    mutation    mutant generation and mutation score
    cli         `vleval` command
"""

__version__ = "0.1.0"
