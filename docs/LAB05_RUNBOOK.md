# Lab 05 – GitOps Under Pressure: runbook, answers, evidence

> **Update:** the real cluster run has since been captured – see `docs/LAB05_EVIDENCE.md` and `docs/evidence/lab05-run.log`. The "Expected"/prediction wording below was written before that run.
>
> **Original status.** Prepared offline. The Git changes below were rendered with
> `kustomize build`, schema-checked with `kubeconform` and policy-checked with
> `scripts/check-restricted.py`; the app was run locally as UID 1000. **No Kubernetes/Argo CD
> cluster was available, so every "Expected" block is a prediction, not captured output.**
> Replace each with your real output before the defense. Missions 3–5 must be pushed as separate
> commits (ideally via PRs) – the commits on branch `lab05-solution` give you the exact changes.

## Before anything: context guard
```bash
kubectl config current-context   # MUST print kind-citybike-gitops
```

## Mission 0 – setup
```bash
bash scripts/preflight.sh
kind create cluster --name citybike-gitops --config kind-config.yaml --wait 180s
kubectl config current-context
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
```
Deliverable: output of the context command + `kubectl -n argocd get pods`.

## Mission 1 – deploy desired state
```bash
cp bootstrap/application.template.yaml bootstrap/application.yaml
sed -i 's#YOUR_USERNAME/citybike-k8s-gitops#AlTAR333/lab05-devops#' bootstrap/application.yaml   # repo is lab05-devops, not the template name
kubectl apply -f bootstrap/application.yaml
kubectl -n argocd get applications.argoproj.io citybike
kubectl -n citybike get deploy,pods,svc
bash scripts/smoke-service.sh
```
Note: the template hard-codes the repo name `citybike-k8s-gitops`; this repo is `lab05-devops`, so replace the whole path.
`bootstrap/application.yaml` is git-ignored – correct.

**Q: Kustomize and the ConfigMap hash?** `configMapGenerator` reads `app/server.js` and emits
`citybike-script-<hash of content>` (currently `citybike-script-6dgthf428d`), and rewrites the Deployment's volume to that name.
Edit `server.js` → new hash → new ConfigMap name → Pod template changes → Kubernetes rolls out new Pods. A fixed name
would update the ConfigMap in place and running Pods would never restart.

**Q: Why Git as source of truth?** It is versioned, reviewable, auditable and reproducible; the cluster can be rebuilt from it.
**Synced** = live resources match what the Git manifests render to. It says nothing about whether the app works
(health is a separate Argo status), and Synced + Healthy can still serve wrong content or have a broken Service
(Mission 3).

## Mission 2 – drift
```bash
kubectl -n citybike scale deployment/citybike --replicas=0
kubectl -n citybike get deployment/citybike -w          # record timestamps: 0/0 -> 2/2
kubectl -n argocd annotate applications.argoproj.io citybike argocd.argoproj.io/refresh=hard --overwrite   # if slow
```
Expected timeline: t0 replicas 2 → t+0s `scale` → 0/0, app OutOfSync → within seconds to ~3 min (watch event or
refresh) controller re-syncs → replicas 2, pods recreated, Synced/Healthy. Do not scale back yourself.

**Q: Why doesn't `kubectl scale` persist?** Git declares `replicas: 2`; with `selfHeal: true` the application controller
treats any live divergence as drift and re-applies the declared state. **If selfHeal were off:** the app would show
OutOfSync but stay at 0 replicas (outage) until someone synced manually; automated sync only fires on Git changes, not on live drift.

## Mission 3 – bad Git change (targetPort 3999)
```bash
git checkout -b feature/broken-service
sed -i 's/targetPort: 3000/targetPort: 3999/' gitops/service.yaml
git commit -am "Break Service targetPort (lab drill)" && git push -u origin feature/broken-service
# open PR, partner reviews, merge to main; then:
kubectl -n argocd annotate applications.argoproj.io citybike argocd.argoproj.io/refresh=hard --overwrite
kubectl -n argocd get applications.argoproj.io citybike     # Synced (!), Healthy
kubectl -n citybike get pods,svc,endpointslice              # pods 2/2 Ready; endpointslice ports show 3999
kubectl -n citybike describe svc citybike                   # TargetPort: 3999/TCP, Endpoints: <ip>:3999
bash scripts/smoke-service.sh                               # FAIL expected
```
**Root cause:** the container listens on 3000 (`containerPort: 3000`, readiness/liveness probe the *pod* directly on
port `http`=3000, so Pods stay Ready). The Service selector still matches the Pods, so endpoints exist, but they point to
port 3999 where nothing listens → connections refused/reset. Probes never traverse the Service, and Argo only compares
manifests, so Synced/Healthy stays green.

**Recovery (Git only):**
```bash
git checkout main && git pull && git revert <bad-commit-sha> && git push origin main
kubectl -n argocd annotate applications.argoproj.io citybike argocd.argoproj.io/refresh=hard --overwrite
bash scripts/smoke-service.sh   # PASS
```
(Prepared commits: `357f3b3` break, `7519355` revert.)

## Mission 4 – Restricted Pod Security
Prepared commits `9503df0` (hardening) and `157b4ad` (APP_RELEASE v1→v2). The hardening diff:
```yaml
spec.template.spec.securityContext:
  runAsNonRoot: true
  runAsUser: 1000          # numeric: image user "node" is a name, kubelet can't verify non-root from a name
  runAsGroup: 1000
  fsGroup: 1000
  seccompProfile: {type: RuntimeDefault}
containers[0].securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: {drop: ["ALL"]}
volumes: + tmp emptyDir (16Mi) mounted at /tmp   # writable scratch so read-only root is safe; probes/features untouched
```
Offline verification: `kustomize build gitops | python3 scripts/check-restricted.py` → baseline **FAIL** (4 violations:
privilege escalation, non-root, seccomp, drop ALL), hardened **PASS**. The app runs fine as UID 1000 (it only uses `node:http`).

Cluster sequence (order matters – warn/audit first, enforce only after a healthy rollout):
```bash
kubectl label namespace citybike pod-security.kubernetes.io/warn=restricted --overwrite
kubectl label namespace citybike pod-security.kubernetes.io/audit=restricted --overwrite
# merge hardening commit to main; wait for Argo
kubectl -n citybike rollout status deployment/citybike --timeout=180s
kubectl label namespace citybike pod-security.kubernetes.io/enforce=restricted --overwrite
# merge APP_RELEASE=v2 commit; wait for Argo
kubectl -n citybike rollout status deployment/citybike --timeout=180s
kubectl -n citybike get pods -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.securityContext.runAsUser}{"\n"}{end}'
bash scripts/smoke-service.sh
```
Why this order: enforcing first would have rejected the un-hardened ReplicaSet's replacement pods; warn/audit first
shows violations without blocking. Because `maxUnavailable: 0`, old pods keep serving during the rollout (no downtime).

| Control | Risk mitigated |
|---|---|
| runAsNonRoot / runAsUser 1000 | container compromise yields root inside the container; limits file/kernel-attack surface |
| allowPrivilegeEscalation: false | setuid/`no_new_privs` escalation to root |
| capabilities drop ALL | raw sockets, chown, mount-style capabilities abuse |
| seccompProfile RuntimeDefault | blocks ~dozens of dangerous syscalls (kernel exploit surface) |
| readOnlyRootFilesystem | malware persistence / tampering with binaries (not required by Restricted; extra hardening) |

Caveat: `pod-security.kubernetes.io/*` labels set with `kubectl label` are live changes made outside Git. They survive
because Argo only creates the namespace (CreateNamespace=true) and doesn't own those labels; for a stricter GitOps setup
declare a `Namespace` manifest with the labels in `gitops/`. Document that trade-off in the defense.

## Mission 5 – readiness failure
Prepared commits `15f154b` (READY_MODE=fail) and `67ac680` (revert).
```bash
kubectl -n citybike rollout status deployment/citybike --timeout=75s   # expected: times out (new ReplicaSet never gets Ready)
kubectl -n citybike get pods          # 2 old Ready + 1 new 0/1 Running
kubectl -n citybike describe deployment citybike   # NewReplicaSet progressing, ProgressDeadlineExceeded after 600s
kubectl -n citybike get events --sort-by=.lastTimestamp | tail
bash scripts/smoke-service.sh         # still PASS – old pods serve
```
Prediction: `maxSurge 1 / maxUnavailable 0` → Kubernetes creates one new Pod, it never turns Ready (readiness returns 503),
so no old Pod is ever terminated; traffic stays on the 2 old Ready Pods. The rollout hangs; Argo reports Synced but
**Progressing → Degraded** after the progress deadline. Fix: revert commit, push, Argo reconciles, new Pods become Ready.

Locally verified behavior of the app: `READY_MODE=ok` → live 200 / ready 200; `READY_MODE=fail` → live 200 / **ready 503**.
**Why separate probes?** Liveness answers "is the process broken, restart it?"; readiness answers "should it receive traffic
right now?". A dependency outage should drain traffic (readiness), not restart-loop the Pod (liveness), which would
add load and hide the cause.

## Mission 6 – defense
- **Why `kubectl apply` in production isn't acceptable:** changes are unreviewed, untracked, not reproducible, and Argo
  selfHeal reverts them anyway (Mission 2); Git gives review, history, rollback (`git revert`) and a single source of truth.
- **Synced but failing:** Synced compares manifests to cluster, not user-visible behavior; a wrong `targetPort` is a valid
  manifest and Pod health checks bypass the Service (Mission 3).

### Evidence checklist (fill in with real captures)
- [ ] M0 context + argocd pods · [ ] M1 Synced/Healthy, 2/2, smoke PASS · [ ] M2 replica timeline
- [ ] M3 failed smoke, `describe svc`, endpointslice, revert commit, passing smoke
- [ ] M4 hardening diff, namespace labels, `rollout status`, smoke · [ ] M5 stalled rollout + recovery
- [ ] Collaboration: **both students author ≥1 commit and review ≥1 PR** (not something that can be prepared by script)
- [ ] No secrets committed (`bootstrap/application.yaml` is git-ignored)
