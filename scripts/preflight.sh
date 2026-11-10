#!/usr/bin/env bash
set -euo pipefail
printf '\n=== CityBike Kubernetes/GitOps prerequisite checks ===\n'
missing=0
for tool in docker kind kubectl git curl bash; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'OK      %-8s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf 'MISSING %-8s : see docs/INSTALL_FIRST.md\n' "$tool"
    missing=1
  fi
done
if [[ "$missing" -ne 0 ]]; then exit 1; fi
if ! docker info >/dev/null 2>&1; then
  echo 'FAIL: Docker daemon unreachable. Start Docker Desktop/Engine and check WSL integration.'
  exit 1
fi
printf '\nDocker: '; docker version --format '{{.Server.Version}}' || true
printf 'kind: '; kind version
printf 'kubectl: '; kubectl version --client 2>/dev/null | head -2 || true
if command -v node >/dev/null 2>&1; then
  printf 'Optional local Node: '; node --version
else
  echo 'Optional: Node.js 22+ needed only for local unit tests.'
fi
for file in kind-config.yaml gitops/deployment.yaml gitops/service.yaml gitops/kustomization.yaml \
            bootstrap/application.template.yaml scripts/smoke-service.sh; do
  if [[ ! -f "$file" ]]; then echo "MISSING source file: $file"; exit 1; fi
done
echo 'PASS: tools/source structure available. GitHub access, Docker images and real Argo cluster remain to be validated.'
