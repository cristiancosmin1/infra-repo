#!/usr/bin/env bash

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-central-1}"
PROJECT_NAME="${PROJECT_NAME:-devops-levelup}"
ENVIRONMENT="${ENVIRONMENT:-staging}"

echo
echo "=============================="
echo "Initializing AWS Secrets..."
echo "=============================="

secret_exists() {
    local secret_name="$1"

    aws secretsmanager describe-secret \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        >/dev/null 2>&1
}

secret_has_value() {
    local secret_name="$1"

    aws secretsmanager get-secret-value \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        >/dev/null 2>&1
}

create_secret_if_missing() {
    local secret_name="$1"

    if secret_exists "${secret_name}"; then
        echo "OK: AWS secret exists: ${secret_name}"
        return
    fi

    echo "Creating AWS secret: ${secret_name}"

    aws secretsmanager create-secret \
        --name "${secret_name}" \
        --region "${AWS_REGION}" \
        --tags \
            Key=Project,Value="${PROJECT_NAME}" \
            Key=Environment,Value="${ENVIRONMENT}" \
            Key=ManagedBy,Value=Bootstrap \
        >/dev/null

    echo "OK: Created ${secret_name}"
}

initialize_shopping_secret() {
    local secret_name="${PROJECT_NAME}/${ENVIRONMENT}/shopping-app"

    create_secret_if_missing "${secret_name}"

    if secret_has_value "${secret_name}"; then
        echo "OK: ${secret_name} already initialized."
        return
    fi

    echo "Initializing ${secret_name}"

    local db_user
    local db_password

    read -r -p "Shopping DB username [shopping]: " db_user
    db_user="${db_user:-shopping}"

    read -r -s -p "Shopping DB password: " db_password
    echo

    if [[ -z "${db_password}" ]]; then
        echo "ERROR: Shopping DB password cannot be empty."
        exit 1
    fi

    local secret_json

    secret_json="$(jq -n \
        --arg user "${db_user}" \
        --arg password "${db_password}" \
        '{
            DB_USER: $user,
            DB_PASSWORD: $password
        }')"

    aws secretsmanager put-secret-value \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --secret-string "${secret_json}" \
        >/dev/null

    echo "OK: ${secret_name} initialized."
}

initialize_keycloak_admin_secret() {
    local secret_name="${PROJECT_NAME}/${ENVIRONMENT}/keycloak-admin"

    create_secret_if_missing "${secret_name}"

    if secret_has_value "${secret_name}"; then
        echo "OK: ${secret_name} already initialized."
        return
    fi

    echo "Initializing ${secret_name}"

    local admin_user
    local admin_password

    read -r -p "Keycloak admin username [admin]: " admin_user
    admin_user="${admin_user:-admin}"

    read -r -s -p "Keycloak admin password: " admin_password
    echo

    if [[ -z "${admin_password}" ]]; then
        echo "ERROR: Keycloak admin password cannot be empty."
        exit 1
    fi

    local secret_json

    secret_json="$(jq -n \
        --arg user "${admin_user}" \
        --arg password "${admin_password}" \
        '{
            KC_BOOTSTRAP_ADMIN_USERNAME: $user,
            KC_BOOTSTRAP_ADMIN_PASSWORD: $password
        }')"

    aws secretsmanager put-secret-value \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --secret-string "${secret_json}" \
        >/dev/null

    echo "OK: ${secret_name} initialized."
}

initialize_keycloak_db_secret() {
    local secret_name="${PROJECT_NAME}/${ENVIRONMENT}/keycloak-db"

    create_secret_if_missing "${secret_name}"

    if secret_has_value "${secret_name}"; then
        echo "OK: ${secret_name} already initialized."
        return
    fi

    echo "Initializing ${secret_name}"

    local db_name
    local db_user
    local db_password

    read -r -p "Keycloak DB name [keycloak]: " db_name
    db_name="${db_name:-keycloak}"

    read -r -p "Keycloak DB username [keycloak]: " db_user
    db_user="${db_user:-keycloak}"

    read -r -s -p "Keycloak DB password: " db_password
    echo

    if [[ -z "${db_password}" ]]; then
        echo "ERROR: Keycloak DB password cannot be empty."
        exit 1
    fi

    local secret_json

    secret_json="$(jq -n \
        --arg db "${db_name}" \
        --arg user "${db_user}" \
        --arg password "${db_password}" \
        '{
            POSTGRES_DB: $db,
            POSTGRES_USER: $user,
            POSTGRES_PASSWORD: $password
        }')"

    aws secretsmanager put-secret-value \
        --secret-id "${secret_name}" \
        --region "${AWS_REGION}" \
        --secret-string "${secret_json}" \
        >/dev/null

    echo "OK: ${secret_name} initialized."
}

wait_for_external_secret() {
    local namespace="$1"
    local name="$2"

    echo "Waiting for ExternalSecret ${namespace}/${name}..."

    for _ in {1..60}; do
        if kubectl get externalsecret "${name}" \
            -n "${namespace}" >/dev/null 2>&1; then

            local ready

            ready="$(kubectl get externalsecret "${name}" \
                -n "${namespace}" \
                -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' \
                2>/dev/null || true)"

            if [[ "${ready}" == "True" ]]; then
                echo "OK: ${namespace}/${name} SecretSynced."
                return
            fi
        fi

        sleep 5
    done

    echo "ERROR: ExternalSecret ${namespace}/${name} did not become ready."
    exit 1
}

initialize_shopping_secret
initialize_keycloak_admin_secret
initialize_keycloak_db_secret

echo
echo "=============================="
echo "Checking External Secrets..."
echo "=============================="

wait_for_external_secret shopping shopping-app-secret
wait_for_external_secret keycloak keycloak-admin
wait_for_external_secret keycloak keycloak-db-secret

echo
echo "External Secrets initialization completed successfully."
