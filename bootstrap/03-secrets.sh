#!/usr/bin/env bash

set -euo pipefail

echo
echo "=============================="
echo "Checking External Secrets..."
echo "=============================="

check_external_secret() {

    local namespace="$1"
    local name="$2"

    if kubectl get externalsecret "${name}" \
        -n "${namespace}" >/dev/null 2>&1
    then
        echo "OK: ${namespace}/${name}"
    else
        echo "ERROR: Missing ExternalSecret ${namespace}/${name}"
        exit 1
    fi
}

check_external_secret shopping shopping-app-secret

echo
echo "External Secrets check completed."
