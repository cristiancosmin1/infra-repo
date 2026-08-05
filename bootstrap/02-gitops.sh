#!/usr/bin/env bash

set -euo pipefail

echo "Checking GitOps..."

if kubectl get application platform-root -n argocd >/dev/null 2>&1; then
    echo "platform-root already installed."
else
    echo "Installing platform-root..."

    kubectl apply \
        -f bootstrap/root-application.yaml
fi

echo
echo "Waiting for platform-root..."

until [[ "$(kubectl get application platform-root \
    -n argocd \
    -o jsonpath='{.status.health.status}')" == "Healthy" ]]
do
    sleep 5
done

echo "platform-root Healthy."
