# Live demo script (about 10 minutes)

## Before the presentation (15 minutes earlier)

Run each line and check the result:

```bash
minikube status                                   # host, kubelet, apiserver: Running
kubectl get pods -A | grep -v Running | grep -v Completed   # should print only the header
cd ~/Desktop/Devops/travel-devops/jenkins && docker compose ps   # jenkins + sonarqube: Up
```

Open 3 terminals and leave them running:

```bash
# Terminal 1
minikube tunnel
# Terminal 2
kubectl port-forward -n monitoring svc/monitoring-kube-prometheus-prometheus 9090:9090
# Terminal 3: free for demo commands
```

Open these browser tabs, logged in, in this order:

1. http://travel.local (the app)
2. https://github.com/StavHomsky/travel-app (branch rules: Settings → Rules)
3. http://localhost:8090/job/travel-app (Jenkins)
4. http://localhost:9000/dashboard?id=travel-app (SonarQube)
5. https://hub.docker.com/u/stavdevops (Docker Hub)
6. http://grafana.local/d/travel-app (Grafana dashboard)
7. http://localhost:9090/alerts (Prometheus alerts)

Make a small, safe code change ready on a branch and merged **before** the
demo (for example a text change), so the pipeline has something new to build.
A full build takes a few minutes, so start it at the beginning of the demo.

## During the demo

### 1. The app (1 min) - tab 1
- Dashboard with charts, the map with pins, add a place.
- Adding a place shows the automatic map position and Wikipedia photo.

### 2. Start the pipeline (1 min) - tab 3
- Click **Build Now**. Explain: manual trigger on purpose, because it deploys.
- Show the stage list while it runs: GitLeaks → tests → SonarQube → quality
  gate → build → Trivy → push → deploy.

### 3. Branch protection (1 min) - tab 2
- `main` requires a pull request; force pushes and deletion are blocked.
- Show a merged PR, e.g. the SonarQube fixes.

### 4. Security scans (2 min) - tab 4
- SonarQube: 0 bugs, 0 vulnerabilities, quality gate passed.
- Show the CSRF finding marked as false positive with the written reason.
- Explain Trivy: found 8 HIGH/CRITICAL in the frontend base image, fixed with
  `apk upgrade`, now 0.

### 5. Kubernetes (2 min) - terminal 3
```bash
kubectl get pods,svc,ingress -n travel
kubectl get deploy -n travel -o wide        # image = stavdevops/...:<commit id>
helm history travel -n travel               # every Jenkins deploy is a revision
```
- Show the probes and limits:
  `kubectl describe deploy travel-backend -n travel | grep -A3 -E "Liveness|Readiness|Limits"`

### 6. Monitoring and logs (2 min) - tabs 6 and 7
- Grafana dashboard: DB up, visited/wishlist, requests, response time.
- Grafana → Explore → Loki → `{namespace="travel"}`: the app's JSON logs.
- Prometheus alerts: 4 rules, all inactive (healthy).

### 7. Break it and watch the alert (2 min) - terminal 3 and tab 7
```bash
kubectl scale statefulset travel-postgres -n travel --replicas=0
```
- Refresh Prometheus alerts: `TravelDatabaseDown` goes Pending, then Firing
  after about 1 minute. The backend pod becomes not Ready (readiness probe).
- Repair it:
```bash
kubectl scale statefulset travel-postgres -n travel --replicas=1
```
- The app works again and no data is lost (persistent volume).

### 8. Terraform (1 min) - terminal 3
```bash
cd ~/Desktop/Devops/travel-devops/terraform
terraform workspace list             # default, * dev
kubectl get pods -n travel-dev       # a second, separate environment
kubectl get secret -n terraform-state  # remote state, one per workspace
```

### 9. Back to Jenkins - tab 3
- The build is green. Show the new image tag on Docker Hub (tab 5) and in
  `kubectl get deploy -n travel -o wide`.

## If something goes wrong

| Problem | Quick fix |
|---|---|
| travel.local does not load | Restart `minikube tunnel` (terminal 1) |
| Prometheus page does not load | Restart the port-forward (terminal 2) |
| Build fails | Open Console Output and explain the failed gate. A failing gate is also a valid demo |
| Database alert does not resolve | `kubectl get pods -n travel` and wait for `travel-postgres-0` to be Ready |
