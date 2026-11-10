#!/usr/bin/env bash
set -euo pipefail
printf '\n--- Cluster context ---\n'; kubectl config current-context
printf '\n--- Argo Application ---\n'; kubectl -n argocd get applications.argoproj.io citybike || true
printf '\n--- Workloads ---\n'; kubectl -n citybike get deploy,pods,svc || true
printf '\n--- Endpoints ---\n'; kubectl -n citybike get endpointslice -l kubernetes.io/service-name=citybike || true
