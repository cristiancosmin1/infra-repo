#!/usr/bin/env bash

set -euo pipefail

echo "Checking prerequisites..."

REQUIRED_COMMANDS=(
  terraform
  aws
  kubectl
  helm
  git
  jq
)

for cmd in "${REQUIRED_COMMANDS[@]}"; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: '${cmd}' is not installed."
    exit 1
  fi

  echo "OK: ${cmd}"
done

echo
echo "Checking AWS credentials..."

aws sts get-caller-identity >/dev/null

echo "OK: AWS credentials are valid."
echo
echo "Prerequisites completed successfully."
