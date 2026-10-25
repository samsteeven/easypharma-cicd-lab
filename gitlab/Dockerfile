# gitlab-ci-local dans un conteneur : Node, git et rsync (que l'outil exige) et le client Docker.
# Le conteneur pilote le démon Docker de l'hôte par son socket ; les jobs sont de vrais conteneurs frères.
FROM docker:27-cli AS docker-cli

FROM node:24-bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends git rsync ca-certificates \
    && rm -rf /var/lib/apt/lists/*
COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
RUN npm install -g gitlab-ci-local@4.77.0
RUN git config --global --add safe.directory '*'
WORKDIR /workspace
ENTRYPOINT ["gitlab-ci-local"]
