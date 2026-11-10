#!/usr/bin/env python3
"""Offline check of a rendered Deployment against the Restricted Pod Security Standard.
Usage: kustomize build gitops | python3 scripts/check-restricted.py
Covers the controls relevant to this app (not a full PSS implementation)."""
import sys, yaml
bad = []
for d in yaml.safe_load_all(sys.stdin):
    if not d or d.get("kind") != "Deployment": continue
    pod = d["spec"]["template"]["spec"]; psc = pod.get("securityContext", {})
    if pod.get("hostNetwork") or pod.get("hostPID") or pod.get("hostIPC"): bad.append("host namespaces")
    for v in pod.get("volumes", []):
        if not set(v) - {"name"} <= {"configMap","emptyDir","secret","projected","downwardAPI","persistentVolumeClaim","csi","ephemeral"}: bad.append(f"volume type {v}")
    for c in pod["containers"] + pod.get("initContainers", []):
        sc, n = c.get("securityContext", {}), c["name"]
        if sc.get("privileged"): bad.append(f"{n}: privileged")
        if sc.get("allowPrivilegeEscalation") is not False: bad.append(f"{n}: allowPrivilegeEscalation must be false")
        if not (sc.get("runAsNonRoot") or psc.get("runAsNonRoot")): bad.append(f"{n}: runAsNonRoot must be true")
        if 0 in (sc.get("runAsUser", psc.get("runAsUser", 1)),): bad.append(f"{n}: runAsUser 0")
        if (sc.get("seccompProfile") or psc.get("seccompProfile") or {}).get("type") not in ("RuntimeDefault","Localhost"): bad.append(f"{n}: seccompProfile RuntimeDefault required")
        caps = sc.get("capabilities", {})
        if "ALL" not in caps.get("drop", []): bad.append(f"{n}: capabilities.drop must include ALL")
        if set(caps.get("add", [])) - {"NET_BIND_SERVICE"}: bad.append(f"{n}: forbidden capabilities.add")
        if not sc.get("readOnlyRootFilesystem"): print(f"note: {n}: readOnlyRootFilesystem not set (best practice, not required by Restricted)")
print("FAIL:\n  - " + "\n  - ".join(bad) if bad else "PASS: Deployment satisfies Restricted PSS controls")
sys.exit(1 if bad else 0)
