# Jenkins + the CLI tools our pipeline uses (copied from their official images).
FROM jenkins/jenkins:lts-jdk21
COPY --from=docker:29.5.3-cli           /usr/local/bin/docker /usr/local/bin/
COPY --from=alpine/helm:4.3.1           /usr/bin/helm         /usr/local/bin/
COPY --from=aquasec/trivy:0.76.1        /usr/local/bin/trivy  /usr/local/bin/
COPY --from=zricethezav/gitleaks:v8.30.1 /usr/bin/gitleaks    /usr/local/bin/
COPY --from=node:24-slim                /usr/local/bin/node   /usr/local/bin/
