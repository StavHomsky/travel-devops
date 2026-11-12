# Deployment

How to set up the whole system from zero on a Mac. Commands assume both
repositories are cloned next to each other:

```
~/Desktop/Devops/travel-app
~/Desktop/Devops/travel-devops
```

## 1. Prerequisites

| Tool | Version used |
|---|---|
| Docker Desktop | 29.x (8 GB memory for Docker) |
| Minikube | 1.38, Kubernetes v1.35 |
| kubectl | 1.34+ |
| Helm | 4.3.1 |
| Terraform | 1.15 |
| Trivy, GitLeaks (optional, for local scans) | 0.76.1, 8.30.1 |

Accounts: GitHub, Docker Hub (with a Read & Write access token).

## 2. Run the app locally with Docker Compose (optional)

```bash
cd ~/Desktop/Devops/travel-app
cp .env.example .env        # then put random values in it:
printf "POSTGRES_PASSWORD=%s\nSECRET_KEY=%s\n" "$(openssl rand -hex 16)" "$(openssl rand -hex 32)" > .env
docker compose up -d --build
```

- App: http://localhost:8080
- API: http://localhost:5001/api/v1/locations

Stop it with `docker compose down` (add `-v` to delete the database).

## 3. Kubernetes cluster

```bash
minikube start --driver=docker --cpus=4 --memory=4000
minikube addons enable ingress
minikube addons enable metrics-server
```

Hostnames used by the Ingresses:

```bash
echo "127.0.0.1 travel.local grafana.local dev.travel.local" | sudo tee -a /etc/hosts
```

Keep this running in its own terminal whenever you open the app in a browser:

```bash
minikube tunnel
```

## 4. Monitoring and logging

```bash
cd ~/Desktop/Devops/travel-devops
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 93.2.0 \
  -n monitoring --create-namespace -f monitoring/kube-prometheus-stack.values.yaml --wait --timeout 10m
helm upgrade --install loki grafana/loki --version 7.6.0 \
  -n monitoring -f monitoring/loki.values.yaml --wait --timeout 10m
helm upgrade --install promtail grafana/promtail --version 6.17.1 \
  -n monitoring -f monitoring/promtail.values.yaml --wait
```

Install monitoring **before** the app: the app's chart creates a
ServiceMonitor and PrometheusRule, which need the Prometheus Operator.

Grafana admin password:

```bash
kubectl get secret -n monitoring monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

## 5. Jenkins and SonarQube

```bash
cd ~/Desktop/Devops/travel-devops/jenkins
docker compose up -d --build
```

- Jenkins: http://localhost:8090 (initial password:
  `docker compose exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword`,
  then install the suggested plugins and the **SonarQube Scanner** plugin)
- SonarQube: http://localhost:9000 (first login `admin` / `admin`)

### SonarQube
1. My Account → Security → generate a **Global Analysis Token**.
2. Allow webhooks to the private Docker network, then create the webhook:
   ```bash
   curl -u admin -X POST "http://localhost:9000/api/settings/set" -d "key=sonar.validateWebhooks" -d "value=false"
   curl -u admin -X POST "http://localhost:9000/api/webhooks/create" -d "name=jenkins" -d "url=http://jenkins:8080/sonarqube-webhook/"
   ```

### Kubeconfig for Jenkins
Jenkins runs on the Minikube Docker network, so it needs the cluster's internal
address:

```bash
kubectl config view --minify --flatten --context minikube > ~/.kube/jenkins-minikube.yaml
sed -i '' 's#server: https://127.0.0.1:[0-9]*#server: https://192.168.49.2:8443#' ~/.kube/jenkins-minikube.yaml
```

### Jenkins configuration
Manage Jenkins → Credentials → Global:

| ID | Kind | Value |
|---|---|---|
| `dockerhub` | Username with password | Docker Hub user + access token |
| `kubeconfig-minikube` | Secret file | `~/.kube/jenkins-minikube.yaml` |
| `helm-secrets` | Secret file | `travel-devops/secrets.local.yaml` (see below) |
| `sonar-token` | Secret text | SonarQube token |

Manage Jenkins → System → SonarQube servers: name `sonarqube`, URL
`http://sonarqube:9000`, token `sonar-token`.
Manage Jenkins → Tools → SonarQube Scanner: name `sonar-scanner`, install
automatically.

`secrets.local.yaml` (git-ignored, never commit it):

```bash
cd ~/Desktop/Devops/travel-devops
printf 'secrets:\n  postgresPassword: "%s"\n  secretKey: "%s"\n' "$(openssl rand -hex 16)" "$(openssl rand -hex 32)" > secrets.local.yaml
```

### Pipeline job
New Item → `travel-app` → Pipeline → Pipeline script from SCM:
- Repository: `https://github.com/StavHomsky/travel-devops.git`
- Branch: `*/main`
- Script path: `jenkins/Jenkinsfile`

## 6. Deploy the app

Jenkins → `travel-app` → **Build Now**. The pipeline tests, scans, builds,
pushes and deploys release `travel` to namespace `travel`.

Check:

```bash
kubectl get pods -n travel
helm history travel -n travel
curl -s http://travel.local/api/v1/stats
```

All deploys go through Jenkins. Running `helm upgrade` by hand without the
pipeline's `--set` image values would switch the app back to the default
`travel-backend:local` image.

## 7. Extra environments with Terraform

```bash
cd ~/Desktop/Devops/travel-devops/terraform
printf 'image_tag = "<commit id>"\npostgres_password = "%s"\nsecret_key = "%s"\n' \
  "$(openssl rand -hex 16)" "$(openssl rand -hex 32)" > secrets.auto.tfvars   # git-ignored

kubectl create namespace terraform-state      # only the first time
terraform init
terraform workspace new dev                   # or: terraform workspace select dev
terraform apply
```

Result: namespace `travel-dev` with the full app at http://dev.travel.local.
State is stored as Secret `tfstate-dev-travel` in namespace `terraform-state`.
For production: `terraform workspace new prod` and `terraform apply`.

Remove an environment with `terraform destroy` in its workspace.

## 8. Where to find things

| What | Where |
|---|---|
| App | http://travel.local |
| Grafana (dashboard "Travel App", logs in Explore → Loki) | http://grafana.local |
| Prometheus | `kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090` → http://localhost:9090 |
| Alertmanager | `kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-alertmanager 9093:9093` → http://localhost:9093 |
| Jenkins | http://localhost:8090 |
| SonarQube | http://localhost:9000 |
| Images | https://hub.docker.com/u/stavdevops |
