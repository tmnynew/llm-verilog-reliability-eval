# Runtime image for the evaluation platform (paper §2.3: Python, Linux container).
# Vivado is not included; mount a licensed installation and set enable_vivado: true if needed.
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive PYTHONUNBUFFERED=1 PYTHONIOENCODING=utf-8
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv \
        iverilog verilator yosys \
        build-essential perl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY pyproject.toml README.md ./
COPY vleval ./vleval
COPY benchmark ./benchmark
COPY configs ./configs
RUN python3 -m venv /venv && /venv/bin/pip install --no-cache-dir -e ".[stats,figures,web]"
ENV PATH="/venv/bin:${PATH}"
# Tool configuration (Icarus simulation, Verilator lint, Yosys pre-screen) regardless of the CWD.
ENV VLEVAL_TOOLS=/app/configs/tools.yaml

# Sanity check at build time: goldens pass, mutation score above threshold.
RUN vleval validate --sim && vleval mutation-score

EXPOSE 8000
CMD ["vleval", "web", "--host", "0.0.0.0", "--port", "8000"]
