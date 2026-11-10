# Lab 05 – Evidence from a real run

Executed on a **real kind cluster (`kind-citybike-gitops`) with Argo CD** inside GitHub Actions
(`.github/workflows/lab05-e2e.yml`, run 42796344814, triggered by pushing branch `run-e2e`).
Argo CD tracked throwaway branch `e2e-run` of this repository, starting at the original starter commit `4d1248d`;
every change below is a Git commit pushed to that branch (see `git log origin/e2e-run`). Nothing was patched live with kubectl
except the deliberate drift in Mission 2 and the namespace labels required by the lab.
Full log: [`evidence/lab05-run.log`](evidence/lab05-run.log) – all 14 automated checks passed.

| Mission | Observed result (from the log) |
|---|---|
| M0 | context `kind-citybike-gitops`; all Argo CD pods Running (repo-server, application-controller …) |
| M1 | Application **Synced / Healthy**, deployment 2/2, smoke PASS (`release: v1`). ConfigMap rendered as `citybike-script-6dgthf428d` |
| M2 | `kubectl scale --replicas=0` at 10:08:19 → `spec.replicas=2` again by 10:08:21 with no manual restore (selfHeal), then 2/2 Healthy and smoke PASS |
| M3 | Bad commit `1bb2921` (targetPort 3999): Argo **Synced/Healthy**, both pods `ready=true`, EndpointSlice port **3999**, `describe svc` shows `Endpoints: 10.244.0.14:3999,…`; smoke **FAIL** (`connect: connection refused` on 3999). Git revert `0a95a7d` → TargetPort 3000, smoke PASS |
| M4 | warn/audit labels, hardened commit `516010c` rolled out; enforcement then enabled (kubectl warned existing un-hardened pods would violate it – expected, they were already replaced); `APP_RELEASE=v2` commit `5901b10` rolled out under `enforce=restricted`, 2/2 Ready, smoke PASS (`release: v2`). Running pod: `runAsNonRoot`, uid 1000, `seccompProfile: RuntimeDefault`, `allowPrivilegeEscalation:false`, `drop: ["ALL"]`, `readOnlyRootFilesystem:true`. A `--privileged` pod was **rejected** by `restricted:latest` ([`evidence/m4-privileged-pod-rejected.txt`](evidence/m4-privileged-pod-rejected.txt)) |
| M5 | `READY_MODE=fail` commit `80914e0`: `rollout status` timed out (exit 1); pods 2 old `1/1` + 1 new `0/1`; ReplicaSets 2 desired / 1 updated / 3 total / 2 available; Argo **Synced + Progressing**; smoke still PASS (old pods serve, `v2`); on the stuck pod `live=200 ready=503`, event `Readiness probe failed: HTTP probe failed with statuscode: 503`. Revert `64520ba` → rollout succeeded, Argo Healthy, smoke PASS |

## Answers backed by the evidence
- **Synced ≠ working:** M3 – Argo reported Synced/Healthy while the Service forwarded to a port nothing listened on. Pod probes hit the pod port directly (3000), never through the Service.
- **Self-heal:** M2 – the live change was reverted in about 2 seconds without human action; with selfHeal off the app would only turn OutOfSync and stay at 0 replicas.
- **Readiness vs liveness:** M5 – the same pod returned 200 on `/health/live` and 503 on `/health/ready`; failing readiness kept it out of the Service and stalled the rollout (`maxUnavailable: 0`) instead of causing downtime or a restart loop.
- **Order of enforcement:** M4 – enforcing before hardening would have rejected replacement pods; warn/audit first made the violations visible (the warning text in the log).

## Honest limitations
- The run executed in CI with one automation identity ("Lab05 Student"). The **two-author / peer-review requirement** is not satisfied by it: your partner must author at least one commit and review at least one PR in this repo.
- Merging `main` PRs #1–#6 happened without a human review; they are visible in the repo history.
- Namespace Pod Security labels were applied with `kubectl label` (as the lab instructs), so they are not stored in Git.
