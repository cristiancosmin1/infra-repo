#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"${SCRIPT_DIR}/01-prerequisites.sh"

"${SCRIPT_DIR}/01b-aws-access.sh"

"${SCRIPT_DIR}/02-gitops.sh"

"${SCRIPT_DIR}/03-secrets.sh"

"${SCRIPT_DIR}/04-keycloak-users.sh"

"${SCRIPT_DIR}/05-verify.sh"
