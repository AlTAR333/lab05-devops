# CityBike - GitOps Under Pressure

A **student starter** for a two-person advanced Kubernetes + Argo CD lab. It is deliberately safe and small: GitOps state is declared in `gitops/`, with no external npm dependencies or proprietary services.

Start with [`docs/SETUP.md`](docs/SETUP.md), then follow the student lab PDF.

## Repository layout
- `gitops/`: declarative Kustomize app (Deployment, Service, generated ConfigMap)
- `bootstrap/`: Argo CD Application template (must customize `YOUR_USERNAME`)
- `scripts/`: prerequisite validation, cluster diagnostics, HTTP smoke test
- `tests/`: Node.js built-in unit tests
- `kind-config.yaml`: single-node local Kubernetes cluster

## Rules
- Use a disposable **kind** cluster only; verify `kubectl config current-context`.
- Do **not** commit credentials, private keys, or Secrets.
- **Do not apply live manifest fixes manually.** Remediate in Git and let Argo CD reconcile.
- Do not email the code ZIP through Gmail (JavaScript files can be blocked). Share via GitHub or Google Drive.
