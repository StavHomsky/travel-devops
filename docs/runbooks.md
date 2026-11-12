# Runbooks

What to do when something breaks. Each alert below is defined in
`helm/travel-app/templates/prometheusrule.yaml` and is visible in Prometheus
(Alerts) and Alertmanager.

Useful commands for every case:

```bash
kubectl get pods -n travel
kubectl describe pod -n travel <pod>
kubectl logs -n travel deploy/travel-backend --tail=50
kubectl logs -n travel deploy/travel-backend -c migrate     # init container
helm history travel -n travel
```

Logs from all pods are also in Grafana → Explore → Loki:
`{namespace="travel"}`, or only errors: `{namespace="travel"} |= "ERROR"`.

---

## TravelBackendDown (critical)

**Meaning:** Prometheus has not been able to scrape any backend pod for
2 minutes. The API is probably down.

**Check:**
1. `kubectl get pods -n travel -l app.kubernetes.io/component=backend`
2. Look at the status:
   - `CrashLoopBackOff`: read `kubectl logs ... --previous`. Common causes are a
     bad config value or a code error in the new version.
   - `Init:Error` / `Init:CrashLoopBackOff`: the migration init container failed.
     Read `kubectl logs ... -c migrate`. Often the database is not reachable
     (see TravelDatabaseDown).
   - `ImagePullBackOff`: the image tag does not exist on Docker Hub, or Docker
     Hub is not reachable.
   - `OOMKilled` in `describe`: the pod used more than its memory limit (256Mi).
   - `Pending`: not enough CPU/memory on the node. Check
     `kubectl describe node minikube`.

**Fix:**
- A bad release: roll back to the previous working revision:
  ```bash
  helm history travel -n travel
  helm rollback travel <revision> -n travel
  ```
  Then fix the code and deploy again through Jenkins.
- Memory: raise `backend.resources.limits.memory` in `values.yaml`, deploy
  through Jenkins.

---

## TravelDatabaseDown (critical)

**Meaning:** The backend runs but `travel_db_up` has been 0 for 1 minute. The
backend's readiness probe fails too, so the API receives no traffic.

**Check:**
1. `kubectl get pods,pvc -n travel` - is `travel-postgres-0` Running and Ready?
2. `kubectl logs -n travel travel-postgres-0`
3. `kubectl exec -n travel travel-postgres-0 -- pg_isready -U travel -d travel`

**Fix:**
- Pod missing or scaled down:
  `kubectl scale statefulset travel-postgres -n travel --replicas=1`
- Pod crashing on start with "password authentication failed" in the backend
  logs: the password in the Secret does not match the one the database was
  created with. Restore the original `secrets.local.yaml` / `helm-secrets`
  credential and redeploy.
- Disk full: check `kubectl exec -n travel travel-postgres-0 -- df -h /var/lib/postgresql/data`
  and increase `postgres.storage`.

Data is on the PersistentVolumeClaim `data-travel-postgres-0`. Deleting or
restarting the pod does not delete data. Never delete the PVC unless you mean
to lose the data.

---

## TravelHighErrorRate (warning)

**Meaning:** More than 5% of API requests returned 5xx for 5 minutes.

**Check:**
1. Grafana → **Travel App** dashboard → "Requests per second (by status code)":
   when did it start, and does it match a deploy (`helm history`)?
2. Loki: `{namespace="travel", container="backend"} |= "ERROR"` to find the
   exception and the endpoint.
3. Is the database healthy? (see TravelDatabaseDown)

**Fix:**
- Started right after a deploy: `helm rollback travel <previous revision> -n travel`,
  then fix and redeploy through Jenkins.
- Database related: follow TravelDatabaseDown.

---

## TravelEnrichmentFailing (warning)

**Meaning:** More than half of the calls to OpenStreetMap or Wikipedia ended
in an error for 15 minutes. The app still works, but new places get no map position,
photo or description.

**Check:**
1. Prometheus: `sum by (source, result) (rate(travel_enrichment_requests_total[15m]))`
   shows which service fails. `result` is `ok`, `not_found` (the place simply
   has no match, not a failure) or `error` (timeout, HTTP error, no network).
   Only `error` counts for this alert.
2. Can the cluster reach the internet?
   ```bash
   kubectl exec -n travel deploy/travel-backend -- python -c \
     "import urllib.request as u; print(u.urlopen('https://en.wikipedia.org', timeout=5).status)"
   ```

**Fix:**
- External service down or rate-limiting us: no action needed; wait. Nominatim
  allows 1 request per second.
- No internet from the cluster: fix the network (e.g. restart Minikube).
- Afterwards, fill in the missing data: in the app, **Import / Export →
  Fetch missing map info**, or `POST /api/v1/locations/enrich-missing`.

---

## Other situations

### The pipeline is red
Open the build → Console Output and find the first failed stage.

| Stage | Typical cause | Action |
|---|---|---|
| Secret scan | A secret was committed | Remove it, **rotate** the secret (it is in git history), rewrite history if needed |
| Lint & test | Code or test error | Fix in a branch → PR |
| Quality gate | New bugs or issues in new code | Open SonarQube, fix, or mark a false positive with a reason |
| Quality gate times out | SonarQube webhook missing | Recreate it (see deployment.md, step 5) |
| Image scan (Trivy) | New CVE with a fix available | Rebuild with updated base images / packages |
| Deploy | Pods not ready in 5 min | Already rolled back automatically. Check pod logs as in TravelBackendDown |

### App not reachable at http://travel.local
1. Is `minikube tunnel` running? It often stops after the Mac sleeps. Restart it.
2. `kubectl get ingress -n travel` should show host `travel.local`.
3. `/etc/hosts` must contain `127.0.0.1 travel.local`.

### Alert rules or new metrics do not appear in Prometheus
After a deploy it takes 1-2 minutes until the operator's new config reaches the
Prometheus pod. Wait, then check Status → Target health and Alerts again.
