# Architecture

Travel Locations is a web app for tracking places you have visited and places
on your wishlist, with a map, ratings and statistics. This document describes
how it is built, deployed and operated, and why.

## Repositories

| Repository | Contents |
|---|---|
| [travel-app](https://github.com/StavHomsky/travel-app) | Application code: Flask API, React frontend, Dockerfiles, Docker Compose, SonarQube settings |
| [travel-devops](https://github.com/StavHomsky/travel-devops) | Everything that runs the app: Helm chart, Jenkins, monitoring, Terraform, docs |

Both `main` branches are protected: no direct pushes, no force pushes, no
deletion. Every change goes through a pull request.

## System overview

```
                         ┌──────────────────── Minikube cluster ─────────────────────┐
                         │                                                           │
 Browser ── travel.local ─▶ NGINX Ingress ─┬─ /api ─▶ travel-backend (Flask, :5000)  │
                         │                 │              │                          │
                         │                 └─ /  ───▶ travel-frontend (nginx, :8080) │
                         │                                │                          │
                         │                      travel-postgres (StatefulSet + PVC)  │
                         │                                                           │
                         │  monitoring namespace:                                    │
                         │   Prometheus ◀─ scrapes /metrics (ServiceMonitor)         │
                         │   Alertmanager ◀─ alert rules (PrometheusRule)            │
                         │   Grafana ◀─ dashboard (ConfigMap) + Prometheus + Loki    │
                         │   Promtail ─▶ Loki (all container logs)                   │
                         └───────────────────────────────────────────────────────────┘

 Jenkins + SonarQube (Docker Compose on the laptop) ─ build ─▶ Docker Hub ─ pull ─▶ cluster
```

The backend also calls two public APIs to enrich new places: OpenStreetMap
Nominatim (map coordinates) and Wikipedia (photo and description).

## Components

| Component | Technology | Notes |
|---|---|---|
| Frontend | React 19, Vite, Recharts, Leaflet | Built to static files, served by unprivileged nginx |
| Backend | Flask, Flask-RESTful, SQLAlchemy, Flask-Migrate, gunicorn | REST API under `/api/v1`, JSON errors, input validation |
| Database | PostgreSQL 16 | StatefulSet with a persistent volume |
| Container images | Multi-stage Docker builds | Non-root users, separate test stage |
| Orchestration | Kubernetes (Minikube), Helm 4 | ConfigMap, Secret, Ingress, probes, resource limits |
| CI/CD | Jenkins declarative pipeline | Lint, test, scan, build, push, deploy |
| Security scanning | GitLeaks, SonarQube, Trivy | Each one can stop the pipeline |
| Registry | Docker Hub (`stavdevops/*`) | Images tagged with the git commit id |
| Monitoring | kube-prometheus-stack | Prometheus, Alertmanager, Grafana |
| Logging | Loki + Promtail | Searchable in Grafana |
| Infrastructure as code | Terraform | Module, Kubernetes remote state, workspaces |

## CI/CD pipeline

The Jenkinsfile is in `travel-devops/jenkins/Jenkinsfile`. It checks out
`travel-app` into `./app` and runs:

| # | Stage | Fails the build when |
|---|---|---|
| 1 | Secret scan (GitLeaks, full history of both repos) | A secret is found |
| 2 | Lint & test backend (flake8 + pytest in the Dockerfile `test` stage) | Lint error or failing test |
| 3 | Lint & test frontend (ESLint + Vitest in the Dockerfile `test` stage) | Lint error or failing test |
| 4 | SonarQube analysis (with backend coverage report) | Analysis error |
| 5 | Quality gate (waits for SonarQube via webhook) | Gate is red |
| 6 | Build runtime images, tag = short commit id | Build error |
| 7 | Image scan (Trivy, HIGH/CRITICAL with a fix available) | Any finding |
| 8 | Push to Docker Hub | Push error |
| 9 | Deploy: `helm upgrade --install ... --wait --rollback-on-failure` | Pods not ready in 5 min (automatic rollback) |

Only images that passed every check are pushed, so nothing unscanned reaches
the registry or the cluster.

## Decisions

### Minikube instead of a cloud cluster
The requirements allow Minikube, EKS or GKE. Minikube is free, runs on one
laptop and is easy to rebuild. The Helm chart and Terraform module only need a
cluster connection, so moving to EKS means changing the provider settings, not
the application setup.

### Separate application and DevOps repositories
Application developers change code and Dockerfiles. Deployment, CI and
infrastructure change separately and have their own history and reviews.

### Multi-stage Dockerfiles with a test stage
Lint and tests run inside `docker build --target test`, so Jenkins needs no
Python or Node.js toolchain and every developer runs exactly the same checks.
Runtime images contain no compilers, tests or `node_modules` (frontend: 91 MB
instead of 544 MB) and run as non-root users (backend uid 10001, nginx uid 101).

### Database migrations in an init container
The backend pod runs `flask db upgrade` (and seeds sample data in dev) in an
init container before gunicorn starts. The API never starts against an old
schema, and if PostgreSQL is not ready yet, Kubernetes retries the init
container.

### Liveness and readiness use different checks
- `/healthz` (liveness) only checks that the process answers.
- `/readyz` (readiness) also checks the database.

If the database goes down, pods stop receiving traffic but are not restarted,
because restarting the API cannot fix the database.

### Image tag = git commit id
Every deployed image can be traced to the exact commit. A rollback is a deploy
of an older tag. Tags like `latest` were not used because Kubernetes does not
see a change when the tag stays the same.

### Secrets never enter git
- Local: `.env` (Docker Compose) and `secrets.local.yaml` (Helm) are git-ignored.
- CI: values come from Jenkins credentials (`dockerhub`, `kubeconfig-minikube`,
  `helm-secrets`, `sonar-token`) and are masked in logs.
- Terraform: secrets come from a git-ignored `secrets.auto.tfvars` and are
  marked `sensitive`.
- GitLeaks scans the full history of both repos on every build.

Kubernetes Secrets are only base64-encoded. In production they would come from
a secret manager such as HashiCorp Vault through `secrets.existingSecret`.

### Manual Jenkins trigger
Builds start with "Build Now". The pipeline deploys, so a person decides when a
change goes live. Jenkins runs on a laptop, so GitHub webhooks could not reach
it anyway.

### Security findings: fix, or accept with a reason
- Trivy found fixable OS vulnerabilities in the frontend base image. Fixed by
  running `apk upgrade` in the runtime stage.
- SonarQube found 7 issues. 6 were fixed through pull requests. One (CSRF
  protection disabled) was marked as a false positive: the API uses no cookies
  or sessions, so CSRF does not apply.
- SonarQube's local-webhook validation (SSRF protection) is disabled because
  Jenkins and SonarQube talk over a private Docker network. In production
  Jenkins would have a real hostname and the protection would stay on.
- SonarQube uses its embedded database, which is fine for a lab but not
  supported for production.
- Jenkins uses the host Docker socket, which equals root on the host. Acceptable
  for a local lab; production would use isolated build agents or Kaniko.

### Monitoring as code
The ServiceMonitor, alert rules and Grafana dashboard live in the application's
Helm chart, so they are versioned and deployed together with the app.

### Terraform state in Kubernetes
The `kubernetes` backend stores state as a Secret in the `terraform-state`
namespace, with locking, and needs no cloud account. Each workspace (`dev`,
`prod`) has its own state and its own namespace (`travel-dev`, `travel-prod`).
On AWS this would be an S3 backend.

## Application metrics

| Metric | Meaning |
|---|---|
| `travel_db_up` | 1 if the database answers, 0 if not |
| `travel_locations{type,status}` | Number of places by type and visited/wishlist |
| `travel_countries` | Number of countries |
| `travel_locations_unmapped` | Places without coordinates |
| `travel_location_events_total{event}` | Created / updated / deleted |
| `travel_enrichment_requests_total{source,result}` | Calls to OpenStreetMap and Wikipedia |
| `flask_http_request_total`, `flask_http_request_duration_seconds` | Requests and latency per endpoint |

`/metrics` is only reachable inside the cluster. The Ingress does not route it.
