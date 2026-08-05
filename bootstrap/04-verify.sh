#!/usr/bin/env bash

set -euo pipefail

echo
echo "=============================="
echo "Platform verification"
echo "=============================="

echo
echo "Applications"

kubectl get applications -n argocd

echo
echo "Nodes"

if kubectl get nodes | grep -q NotReady
then
    fail "Nodes"
else
    pass "Nodes"
fi

echo

if kubectl get applications -n argocd \
    | grep -E "Degraded|Missing"
then
    fail "Applications"
else
    pass "Applications"
fi

echo
echo "PVC"

if kubectl get pvc -A \
    | grep Pending
then
    fail "Persistent Volumes"
else
    pass "Persistent Volumes"
fi
echo
echo "External Secrets"

kubectl get externalsecret -A

echo
echo "ClusterSecretStore"

kubectl get clustersecretstore

echo

if kubectl get pods -n shopping \
    | grep -E "CrashLoopBackOff|Error|Pending"
then
    fail "Shopping"
else
    pass "Shopping"
fi

echo

if kubectl get pods -n keycloak \
    | grep -E "CrashLoopBackOff|Error|Pending|CreateContainerConfigError"
then
    fail "Keycloak"
else
    pass "Keycloak"
fi
echo "Verification completed."
