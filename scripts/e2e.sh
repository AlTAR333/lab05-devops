#!/usr/bin/env bash
# Runs Lab 05 Missions 0-5 end to end on a disposable kind cluster (CI use).
# Argo CD tracks branch $E2E_BRANCH of this repo; every "Git change" is a real commit pushed to that branch.
set -uo pipefail
REPO_URL="${REPO_URL:?}"; BR="${E2E_BRANCH:-e2e-run}"; BASE="${BASE_COMMIT:?}"
EVD="${EVIDENCE_DIR:-evidence}"; mkdir -p "$EVD"
ARGO() { kubectl -n argocd "$@"; }
hr() { printf '\n######## %s ########\n' "$*"; }
refresh() { ARGO annotate applications.argoproj.io citybike argocd.argoproj.io/refresh=hard --overwrite >/dev/null; }
app() { ARGO get applications.argoproj.io citybike -o jsonpath='sync={.status.sync.status} health={.status.health.status} rev={.status.sync.revision}'; echo; }
push_commit() { git push -q -f origin "HEAD:refs/heads/$BR"; HEAD_SHA=$(git rev-parse HEAD); }
wait_synced() { # wait until Argo reports Synced at current HEAD (timeout 300s)
  refresh; for i in $(seq 1 60); do
    s=$(ARGO get applications.argoproj.io citybike -o jsonpath='{.status.sync.status} {.status.sync.revision}' 2>/dev/null)
    [ "$s" = "Synced $HEAD_SHA" ] && { echo "Argo Synced at ${HEAD_SHA:0:7}"; return 0; }
    [ $((i%6)) -eq 0 ] && refresh; sleep 5; done; echo "TIMEOUT waiting for Synced at $HEAD_SHA"; app; return 1; }
wait_healthy() { for i in $(seq 1 60); do
    h=$(ARGO get applications.argoproj.io citybike -o jsonpath='{.status.health.status}' 2>/dev/null); [ "$h" = Healthy ] && { echo "Argo Healthy"; return 0; }; sleep 5; done; echo "TIMEOUT waiting Healthy"; app; return 1; }
ts() { date -u +%H:%M:%S; }
RESULT=0; check() { # check "<label>" <command...>
  local label="$1"; shift; if "$@"; then echo "RESULT PASS: $label"; else echo "RESULT FAIL: $label"; RESULT=1; fi; }
gitc() { git -c user.name="Lab05 Student" -c user.email="class-safe@example.com" "$@"; }

hr "MISSION 0 - setup"
kubectl config current-context
[ "$(kubectl config current-context)" = "kind-citybike-gitops" ] || { echo "WRONG CONTEXT"; exit 1; }
ARGO rollout status deployment/argocd-repo-server --timeout=300s
ARGO rollout status statefulset/argocd-application-controller --timeout=300s
ARGO get pods

hr "MISSION 1 - deploy desired state (branch $BR starts at the original starter commit ${BASE:0:7})"
gitc checkout -q -B "$BR" "$BASE"; push_commit
echo "--- kustomize render (ConfigMap name hash):"; kubectl kustomize gitops | grep -m1 "name: citybike-script"
sed "s#https://github.com/YOUR_USERNAME/citybike-k8s-gitops.git#${REPO_URL}#; s#targetRevision: main#targetRevision: ${BR}#" bootstrap/application.template.yaml > bootstrap/application.yaml
cat bootstrap/application.yaml
kubectl apply -f bootstrap/application.yaml
wait_synced; kubectl -n citybike rollout status deployment/citybike --timeout=240s; wait_healthy
kubectl -n argocd get applications.argoproj.io citybike; kubectl -n citybike get deploy,pods,svc
check "M1 smoke" bash scripts/smoke-service.sh

hr "MISSION 2 - drift"
echo "[$(ts)] BEFORE: $(kubectl -n citybike get deploy citybike -o jsonpath='replicas={.spec.replicas} ready={.status.readyReplicas}')"
kubectl -n citybike scale deployment/citybike --replicas=0; echo "[$(ts)] scaled to 0 manually"
sleep 2; echo "[$(ts)] app status: $(app)"
ok=0; for i in $(seq 1 80); do r=$(kubectl -n citybike get deploy citybike -o jsonpath='{.spec.replicas}'); [ "$r" = 2 ] && { ok=1; break; }; [ $i -eq 20 ] && refresh; sleep 3; done
echo "[$(ts)] AFTER: $(kubectl -n citybike get deploy citybike -o jsonpath='spec.replicas={.spec.replicas}')  (self-healed without manual restore: $ok)"
kubectl -n citybike rollout status deployment/citybike --timeout=180s; app
check "M2 self-heal" test "$ok" = 1
check "M2 smoke after heal" bash scripts/smoke-service.sh

hr "MISSION 3 - Git-delivered outage"
sed -i 's/targetPort: 3000/targetPort: 3999/' gitops/service.yaml
gitc commit -qam "Mission 3: [INCIDENT] change Service targetPort to 3999 (intentional break)"; push_commit; BAD=$HEAD_SHA
wait_synced; sleep 8
kubectl -n argocd get applications.argoproj.io citybike
kubectl -n citybike get pods,svc,endpointslice
kubectl -n citybike describe svc citybike | grep -E "Selector|Port|TargetPort|Endpoints"
echo "--- pods still Ready (probes hit the pod port directly):"; kubectl -n citybike get pods -o jsonpath='{range .items[*]}{.metadata.name}{" ready="}{.status.containerStatuses[0].ready}{"\n"}{end}'
echo "--- smoke (FAILURE EXPECTED):"; if bash scripts/smoke-service.sh; then echo "RESULT FAIL: M3 smoke should have failed"; RESULT=1; else echo "RESULT PASS: M3 smoke failed as expected"; fi
echo "--- Revert via Git:"; gitc revert --no-edit "$BAD" >/dev/null; push_commit; wait_synced; sleep 8
kubectl -n citybike describe svc citybike | grep -E "TargetPort|Endpoints"
check "M3 smoke after Git revert" bash scripts/smoke-service.sh

hr "MISSION 4 - Restricted Pod Security"
kubectl label namespace citybike pod-security.kubernetes.io/warn=restricted --overwrite
kubectl label namespace citybike pod-security.kubernetes.io/audit=restricted --overwrite
gitc cherry-pick "$HARDEN_COMMIT" >/dev/null && push_commit; wait_synced
kubectl -n citybike rollout status deployment/citybike --timeout=180s; check "M4 hardened rollout" test $? -eq 0
kubectl label namespace citybike pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl get ns citybike --show-labels
gitc cherry-pick "$RELEASE_COMMIT" >/dev/null && push_commit; wait_synced
kubectl -n citybike rollout status deployment/citybike --timeout=180s; check "M4 rollout under enforce=restricted" test $? -eq 0
kubectl -n citybike get deploy,pods -o wide
echo "--- security context of a running pod:"; kubectl -n citybike get pod -l app.kubernetes.io/name=citybike -o jsonpath='{.items[0].spec.securityContext}{"\n"}{.items[0].spec.containers[0].securityContext}{"\n"}'
echo "--- proof enforcement is real: privileged pod must be rejected"
kubectl -n citybike run bad --image=node:22-alpine --privileged --restart=Never 2>&1 | tail -3 | tee "$EVD/m4-rejected.txt"; grep -qi "forbidden\|violates" "$EVD/m4-rejected.txt" && echo "RESULT PASS: privileged pod rejected" || { echo "RESULT FAIL: privileged pod not rejected"; RESULT=1; kubectl -n citybike delete pod bad --ignore-not-found; }
kubectl -n citybike get deploy citybike; wait_healthy; check "M4 smoke" bash scripts/smoke-service.sh

hr "MISSION 5 - readiness failure"
gitc cherry-pick "$READY_FAIL_COMMIT" >/dev/null && push_commit; BADR=$HEAD_SHA; wait_synced
kubectl -n citybike rollout status deployment/citybike --timeout=75s; echo "rollout status exit code: $? (non-zero = stalled, expected)"
kubectl -n citybike get pods
kubectl -n citybike describe deployment citybike | sed -n '/Replicas:/p;/Conditions:/,/OldReplicaSets/p'
kubectl -n citybike get rs
echo "--- argo status during stalled rollout: $(app)"
echo "--- old pods still serve traffic:"; check "M5 smoke during failed rollout" bash scripts/smoke-service.sh
echo "--- probes compared on the stuck new pod:"
NEWPOD=$(kubectl -n citybike get pods --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1:].metadata.name}')
kubectl -n citybike port-forward "pod/$NEWPOD" 18090:3000 >/dev/null 2>&1 & PF=$!; sleep 3
echo "live=$(curl -s -o /dev/null -w %{http_code} localhost:18090/health/live) ready=$(curl -s -o /dev/null -w %{http_code} localhost:18090/health/ready)"; kill $PF 2>/dev/null
kubectl -n citybike describe pod "$NEWPOD" | grep -E "Readiness|Ready:|Unhealthy" | head -5
echo "--- fix via Git revert:"; gitc revert --no-edit "$BADR" >/dev/null; push_commit; wait_synced
kubectl -n citybike rollout status deployment/citybike --timeout=240s; check "M5 healthy rollout after fix" test $? -eq 0
wait_healthy; kubectl -n citybike get deploy,pods; check "M5 final smoke" bash scripts/smoke-service.sh
hr "FINAL"; app; git log --oneline "$BASE..HEAD"
[ $RESULT -eq 0 ] && echo "ALL CHECKS PASSED" || echo "SOME CHECKS FAILED"
exit $RESULT
