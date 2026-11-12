# Travel App – DevOps

Infrastructure for [travel-app](https://github.com/StavHomsky/travel-app):
how it is packaged, deployed to Kubernetes, tested and released by Jenkins,
and monitored.

## Architecture

```
GitHub (travel-app, travel-devops)
        │ checkout
        ▼
Jenkins ── GitLeaks → lint & test → SonarQube gate → build → Trivy → push → helm deploy
        │                                                         │
        ▼                                                         ▼
Docker Hub (stavdevops/travel-*:<commit sha>)          Minikube cluster
                                                          ns travel:      Ingress → frontend (Nginx) / backend (Flask) → PostgreSQL
                                                          ns monitoring:  Prometheus, Alertmanager, Grafana, Loki, Promtail
```

## Repository structure

```
helm/travel-app/      Helm chart: Deployments, StatefulSet, Services, Ingress,
                      ConfigMap, Secret, probes, resources, ServiceMonitor,
                      PrometheusRule, Grafana dashboard
jenkins/              Jenkins image (Dockerfile), docker-compose for Jenkins + SonarQube,
                      Jenkinsfile
monitoring/           Helm values for kube-prometheus-stack, Loki, Promtail
terraform/            module travel-app, Kubernetes remote state backend, workspaces
docs/                 architecture, deployment, runbooks, demo script
```

## Quick start

Full step-by-step instructions are in [docs/deployment.md](docs/deployment.md).
In short:

```bash
# 1. Cluster
minikube start --driver=docker --cpus=4 --memory=4000
minikube addons enable ingress
minikube addons enable metrics-server
echo "127.0.0.1 travel.local grafana.local dev.travel.local" | sudo tee -a /etc/hosts
minikube tunnel                          # keep running in its own terminal

# 2. Monitoring (exact flags in docs/deployment.md)
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 93.2.0 -n monitoring --create-namespace -f monitoring/kube-prometheus-stack.values.yaml
helm upgrade --install loki grafana/loki --version 7.6.0 -n monitoring -f monitoring/loki.values.yaml
helm upgrade --install promtail grafana/promtail --version 6.17.1 -n monitoring -f monitoring/promtail.values.yaml

# 3. Jenkins + SonarQube
cd jenkins && docker compose up -d --build
# http://localhost:8090 (Jenkins), http://localhost:9000 (SonarQube)

# 4. Deploy: in Jenkins, run the travel-app pipeline (Build Now)
```

The app is then at http://travel.local and Grafana at http://grafana.local.

## CI/CD pipeline

| Stage | What it does | Fails the build when |
|---|---|---|
| Checkout | Pulls travel-app from GitHub, tags images with the short commit SHA | – |
| Secret scan | GitLeaks over the git history of both repos | a secret is found |
| Lint & test | `docker build --target test` for backend and frontend | lint or a test fails |
| SonarQube | Code analysis with coverage, waits for the quality gate | the gate fails |
| Build images | Production images | – |
| Image scan | Trivy, HIGH and CRITICAL with a fix available | a vulnerability is found |
| Push | Pushes both images to Docker Hub | – |
| Deploy | `helm upgrade --install --wait --rollback-on-failure` | pods are not ready in 5 min (rolls back) |

Credentials (Docker Hub, kubeconfig, Helm secrets, Sonar token) are stored in
Jenkins credentials, never in the repository.

## Secrets

Real secret values are never committed. `secrets.local.yaml` (Helm) and
`*.tfvars` (Terraform) are git-ignored. Jenkins receives the Helm secrets as a
secret file credential.

## Monitoring

- Prometheus scrapes the backend `/metrics` through a ServiceMonitor.
- Four alert rules: backend down, database down, high error rate, enrichment failing.
- Grafana dashboard "Travel App" is provisioned from the chart.
- Promtail ships all pod logs to Loki, searchable in Grafana Explore.

## Terraform

```bash
cd terraform
terraform init
terraform workspace new dev
terraform apply        # creates namespace travel-dev with the app
```

State is stored as a Kubernetes Secret (namespace `terraform-state`), one per workspace.

## More documentation

- [docs/architecture.md](docs/architecture.md) – design decisions
- [docs/deployment.md](docs/deployment.md) – full setup from zero
- [docs/runbooks.md](docs/runbooks.md) – what to do when an alert fires
- [docs/demo.md](docs/demo.md) – live demo script
