# INSTALL FIRST - CityBike Kubernetes / GitOps lab

This file supplements the expanded PDF `Lab05_Kubernetes_GitOps_Student_Complete_EN.pdf` in the student pack. Read the PDF's Installation Appendix before Mission 0.

## Operating systems

* Windows 11: install WSL2 Ubuntu (https://learn.microsoft.com/windows/wsl/install), Docker Desktop with WSL integration, then Git/curl/kind/kubectl *inside* WSL2. Use the Ubuntu shell and Linux home directory.
* macOS: install and start Docker Desktop; with Homebrew you can run `brew install git kind kubectl`. `curl` and `bash` normally exist.
* Ubuntu: install Docker Engine from https://docs.docker.com/engine/install/ubuntu/ ; `sudo apt update && sudo apt install -y git curl bash ca-certificates`; install kind/kubectl from official pages.

Official kind: https://kind.sigs.k8s.io/docs/user/quick-start/ ; kubectl: https://kubernetes.io/docs/tasks/tools/ .

## Verify all required tools

```bash
git --version
docker info
kind version
kubectl version --client
curl --version
bash scripts/preflight.sh
```

## Publish the source from THIS directory

Make a NEW EMPTY public repo named citybike-k8s-gitops. Do NOT commit credentials or personal data.

```bash
git init -b main
git config user.name "Your Name"
git config user.email "class-safe@example.com"
git add .
git commit -m "Initialize CityBike GitOps lab"
git remote add origin https://github.com/YOUR_USERNAME/citybike-k8s-gitops.git
git push -u origin main
```

## Bootstrapping

```bash
kind create cluster --name citybike-gitops --config kind-config.yaml --wait 180s
kubectl config current-context  # MUST be kind-citybike-gitops
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f   https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
cp bootstrap/application.template.yaml bootstrap/application.yaml
# EDIT bootstrap/application.yaml and replace YOUR_USERNAME
kubectl apply -f bootstrap/application.yaml
kubectl -n argocd get applications.argoproj.io citybike
kubectl -n citybike get deployment,pods,service
bash scripts/smoke-service.sh
```

### Precautions

- Use *only* a disposable kind cluster; check kubectl context before every destructive action.
- Keep Argo CD deployment state in version-controlled `gitops/`; fix failures with commits and allow reconciliation.
- If Argo is already installed, `kubectl create namespace argocd` may say AlreadyExists.
- The lab intentionally includes technical challenges; incomplete hardening is part of the assignment, not missing source code.
- Runtime and image installation require internet access. A real-cluster rehearsal remains necessary; static validation is not an end-to-end Kubernetes test.
