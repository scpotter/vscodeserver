FROM codercom/code-server:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && rm -rf /var/lib/apt/lists/*

USER coder
WORKDIR /home/coder
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/coder/.local/bin:${PATH}"
