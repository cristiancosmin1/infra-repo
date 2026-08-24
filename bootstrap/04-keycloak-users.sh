#!/usr/bin/env bash

set -euo pipefail

AWS_REGION="${AWS_REGION:-eu-central-1}"
PROJECT_NAME="${PROJECT_NAME:-devops-levelup}"
ENVIRONMENT="${ENVIRONMENT:-staging}"

KEYCLOAK_NAMESPACE="${KEYCLOAK_NAMESPACE:-keycloak}"
KEYCLOAK_POD="${KEYCLOAK_POD:-keycloak-keycloakx-0}"
REALM="${REALM:-devops-lvlup}"

USERS_SECRET="${PROJECT_NAME}/${ENVIRONMENT}/keycloak-users"

echo
echo "=============================="
echo "Provisioning Keycloak users..."
echo "=============================="

wait_for_keycloak() {
    echo "Waiting for Keycloak..."

    for _ in {1..60}; do
        if kubectl get pod "${KEYCLOAK_POD}" \
            -n "${KEYCLOAK_NAMESPACE}" \
            >/dev/null 2>&1; then

            local ready

            ready="$(
                kubectl get pod "${KEYCLOAK_POD}" \
                    -n "${KEYCLOAK_NAMESPACE}" \
                    -o jsonpath='{.status.containerStatuses[0].ready}' \
                    2>/dev/null || true
            )"

            if [[ "${ready}" == "true" ]]; then
                echo "OK: Keycloak is ready."
                return
            fi
        fi

        sleep 5
    done

    echo "ERROR: Keycloak did not become ready."
    exit 1
}

get_users_secret() {
    aws secretsmanager get-secret-value \
        --secret-id "${USERS_SECRET}" \
        --region "${AWS_REGION}" \
        --query SecretString \
        --output text
}

keycloak_exec() {
    kubectl exec \
        -n "${KEYCLOAK_NAMESPACE}" \
        "${KEYCLOAK_POD}" \
        -- sh -c "$1"
}

authenticate_kcadm() {
    keycloak_exec '
        /opt/keycloak/bin/kcadm.sh config credentials \
            --server http://localhost:8080 \
            --realm master \
            --user "$KC_BOOTSTRAP_ADMIN_USERNAME" \
            --password "$KC_BOOTSTRAP_ADMIN_PASSWORD" \
            >/dev/null
    '
}

realm_exists() {
    local realm_name="$1"

    authenticate_kcadm

    keycloak_exec "
        /opt/keycloak/bin/kcadm.sh get realms/${realm_name} \
            >/dev/null 2>&1
    "
}

user_id() {
    local username="$1"

    authenticate_kcadm

    keycloak_exec "
        /opt/keycloak/bin/kcadm.sh get users \
            -r '${REALM}' \
            -q username='${username}' \
            --fields id,username
    " | jq -r --arg username "${username}" \
        '.[] | select(.username == $username) | .id' | head -n1
}

create_user_if_missing() {
    local username="$1"

    local id
    id="$(user_id "${username}")"

    if [[ -n "${id}" && "${id}" != "null" ]]; then
        echo "OK: User ${username} already exists."
        return
    fi

    echo "Creating Keycloak user: ${username}"

    authenticate_kcadm

    keycloak_exec "
        /opt/keycloak/bin/kcadm.sh create users \
            -r '${REALM}' \
            -s username='${username}' \
            -s enabled=true \
            >/dev/null
    "

    echo "OK: User ${username} created."
}

configure_user_profile() {
    local username="$1"
    local first_name="$2"
    local last_name="$3"
    local email="$4"

    local id
    id="$(user_id "${username}")"

    if [[ -z "${id}" || "${id}" == "null" ]]; then
        echo "ERROR: Cannot configure profile for missing user ${username}."
        exit 1
    fi

    authenticate_kcadm

    keycloak_exec "
        /opt/keycloak/bin/kcadm.sh update users/${id} \
            -r '${REALM}' \
            -s firstName='${first_name}' \
            -s lastName='${last_name}' \
            -s email='${email}' \
            -s emailVerified=true \
            -s requiredActions=[] \
            >/dev/null
    "

    echo "OK: Profile configured for ${username}."
}

set_user_password() {
    local username="$1"
    local password="$2"

    authenticate_kcadm

    keycloak_exec "
        /opt/keycloak/bin/kcadm.sh set-password \
            -r '${REALM}' \
            --username '${username}' \
            --new-password '${password}' \
            >/dev/null
    "

    echo "OK: Password configured for ${username}."
}

assign_realm_role() {
    local username="$1"
    local role="$2"

    authenticate_kcadm

    keycloak_exec "
        /opt/keycloak/bin/kcadm.sh add-roles \
            -r '${REALM}' \
            --uusername '${username}' \
            --rolename '${role}' \
            >/dev/null 2>&1 || true
    "

    echo "OK: ${username} has role ${role}."
}

provision_user() {
    local username="$1"
    local password="$2"
    local role="$3"
    local first_name="$4"
    local last_name="$5"
    local email="$6"

    echo
    echo "Configuring ${username} -> ${role}"

    create_user_if_missing "${username}"
    configure_user_profile \
        "${username}" \
        "${first_name}" \
        "${last_name}" \
        "${email}"
    set_user_password "${username}" "${password}"
    assign_realm_role "${username}" "${role}"
}

wait_for_keycloak

if ! realm_exists "${REALM}"; then
    echo "ERROR: Realm ${REALM} does not exist."
    exit 1
fi

echo "OK: Realm ${REALM} exists."

USERS_JSON="$(get_users_secret)"

ALICE_PASSWORD="$(jq -r '.ALICE_PASSWORD' <<< "${USERS_JSON}")"
BOB_PASSWORD="$(jq -r '.BOB_PASSWORD' <<< "${USERS_JSON}")"
ADMIN_PASSWORD="$(jq -r '.ADMIN_PASSWORD' <<< "${USERS_JSON}")"

if [[ \
    -z "${ALICE_PASSWORD}" || "${ALICE_PASSWORD}" == "null" || \
    -z "${BOB_PASSWORD}" || "${BOB_PASSWORD}" == "null" || \
    -z "${ADMIN_PASSWORD}" || "${ADMIN_PASSWORD}" == "null" \
]]; then
    echo "ERROR: Missing Keycloak user credentials in AWS Secrets Manager."
    exit 1
fi

provision_user \
    "alice" \
    "${ALICE_PASSWORD}" \
    "writer" \
    "Alice" \
    "Writer" \
    "alice@example.local"

provision_user \
    "bob" \
    "${BOB_PASSWORD}" \
    "reader" \
    "Bob" \
    "Reader" \
    "bob@example.local"

provision_user \
    "admin" \
    "${ADMIN_PASSWORD}" \
    "admin" \
    "Application" \
    "Admin" \
    "admin@example.local"

echo
echo "Keycloak user provisioning completed successfully."
