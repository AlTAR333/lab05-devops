> **MANDATORY FIRST STEP:** Read `docs/INSTALL_FIRST.md` and the Installation Appendix of the included student PDF before starting Mission 0.

# Setup checklist (instructor and students)

This is a Kubernetes + Argo CD workshop, **not** a Docker optimization lab. It requires a local cluster and a Git repository accessible to Argo CD.

## Local prerequisites (install before the timed class)
- Docker Desktop or Docker Engine with enough free resources. For Windows, WSL2 with Bash is recommended.
- `kind` (Kubernetes in Docker), `kubectl`, `git`, `curl`, and a Bash-compatible shell.
- Internet access to pull the kind node image, Node.js container, Argo CD manifests/images, and to let Argo CD read a **public** GitHub repo.
- GitHub account with permission to publish a throwaway **public** repo without any secrets.
- Node.js 22+ locally is *optional* but useful to run `node --test tests/server.test.js`.

Official references:
- https://kind.sigs.k8s.io/docs/user/quick-start/
- https://argo-cd.readthedocs.io/en/stable/getting_started/
- https://kubernetes.io/docs/concepts/security/pod-security-standards/

## Bootstrapping

```bash
bash scripts/preflight.sh
kind create cluster --name citybike-gitops --config kind-config.yaml
kubectl config current-context   # expected kind-citybike-gitops
kubectl create namespace argocd
kubectl apply -n argocd --server-side --force-conflicts -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deployment/argocd-repo-server --timeout=300s
```

**Never run this exercise against a real production cluster.** Always check the current context before applying or deleting anything.

## Publish your GitOps repository
1. Initialize Git in this **starter project folder**, commit and push it to a newly created, *empty, public* GitHub repo named `citybike-k8s-gitops`. Do not create a README via GitHub because the project includes one.
2. Copy `bootstrap/application.template.yaml` to `bootstrap/application.yaml` and replace `YOUR_USERNAME` with your actual GitHub user name. **Do not apply the template with the placeholder unchanged.**
3. Apply the Application: `kubectl apply -f bootstrap/application.yaml`.
4. The application should become `Synced` and `Healthy` once Argo CD has pulled the Git repository and Kubernetes has downloaded the Node container image. It may take a few minutes.
5. `bash scripts/smoke-service.sh` tests access through the Service.

```bash
git init -b main
git add .
git commit -m "Initialize CityBike Kubernetes lab"
git remote add origin https://github.com/YOUR_USERNAME/citybike-k8s-gitops.git
git push -u origin main
cp bootstrap/application.template.yaml bootstrap/application.yaml
# edit the URL in bootstrap/application.yaml to your public GitHub repository
kubectl apply -f bootstrap/application.yaml
kubectl -n argocd get applications.argoproj.io citybike -w
bash scripts/smoke-service.sh
```

Use a **public code-only repository** because Argo CD otherwise needs repository credentials. Do not put any password, GitHub token, personal data, or Kubernetes Secret literal into Git. The Kubernetes container uses a prebuilt public Node.js base image; no local Docker build is required.

## Helpful operations

```bash
kubectl -n argocd annotate applications.argoproj.io citybike argocd.argoproj.io/refresh=hard --overwrite
kubectl -n citybike get pods -w
kubectl -n citybike describe deployment citybike
kubectl -n citybike get svc citybike -o yaml
```

**Be patient:** Argo CD polls Git rather than reacting synchronously to each push. Refresh the Application if you need to accelerate reconciliation; do not assume the Git state changed just because a push succeeded.

## Local validation without Kubernetes
`node --test tests/server.test.js` tests only the Node app and health endpoints. Passing local tests does **not** prove that the live Kubernetes/Argo installation is correct.
