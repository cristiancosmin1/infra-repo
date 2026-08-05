#!/usr/bin/env bash

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-central-1}"
SHOPPING_SECRET_ID="${SHOPPING_SECRET_ID:-devops-levelup/staging/shopping-app}"

if ! aws secretsmanager describe-secret \
  --secret-id "${SHOPPING_SECRET_ID}" \
  --region "${AWS_REGION}" \
  >/dev/null 2>&1; then
  echo "Secret container does not exist: ${SHOPPING_SECRET_ID}" >&2
  echo "Run terraform apply first." >&2
  exit 1
fi

if aws secretsmanager get-secret-value \
  --secret-id "${SHOPPING_SECRET_ID}" \
  --region "${AWS_REGION}" \
  --query SecretString \
  --output text \
  >/dev/null 2>&1; then
  echo "Secret already initialized: ${SHOPPING_SECRET_ID}"
  exit 0
fi

read -r -p "Shopping DB user: " DB_USER
read -r -s -p "Shopping DB password: " DB_PASSWORD
echo

if [[ -z "${DB_USER}" || -z "${DB_PASSWORD}" ]]; then
  echo "Username and password must not be empty." >&2
  exit 1
fi

SECRET_JSON="$(
  jq -n \
    --arg DB_USER "${DB_USER}" \
    --arg DB_PASSWORD "${DB_PASSWORD}" \
    '{DB_USER: $DB_USER, DB_PASSWORD: $DB_PASSWORD}'
)"

aws secretsmanager put-secret-value \
  --secret-id "${SHOPPING_SECRET_ID}" \
  --region "${AWS_REGION}" \
  --secret-string "${SECRET_JSON}" \
  >/dev/null

unset DB_USER DB_PASSWORD SECRET_JSON

echo "Secret initialized: ${SHOPPING_SECRET_ID}"
