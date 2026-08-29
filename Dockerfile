FROM codercom/code-server:latest

USER root
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates gnupg apt-transport-https shellcheck && curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | bash && apt-get update && apt-get install -y --no-install-recommends infisical && rm -rf /var/lib/apt/lists/*

USER coder
WORKDIR /home/coder
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/coder/.local/bin:${PATH}"
