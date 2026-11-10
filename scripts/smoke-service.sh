#!/usr/bin/env bash
# Run this from a Bash-like shell after the Argo CD application is deployed.
set -euo pipefail
LOGFILE=$(mktemp)
PORT=${PORT:-18080}
kubectl -n citybike port-forward svc/citybike "${PORT}:80" >"${LOGFILE}" 2>&1 &
PF_PID=$!
cleanup() { kill "$PF_PID" 2>/dev/null || true; wait "$PF_PID" 2>/dev/null || true; rm -f "$LOGFILE"; }
trap cleanup EXIT
for n in $(seq 1 25); do
  if curl --silent --show-error --fail --max-time 2 "http://127.0.0.1:${PORT}/health/ready" >/dev/null 2>&1; then
    curl --silent --show-error --fail "http://127.0.0.1:${PORT}/api/stations"
    printf '\nPASS: Service is reachable on port %s\n' "$PORT"
    exit 0
  fi
  if ! kill -0 "$PF_PID" 2>/dev/null; then break; fi
  sleep 1
done
printf 'FAIL: Service is unreachable. Port-forward details:\n' >&2
cat "$LOGFILE" >&2
exit 1
