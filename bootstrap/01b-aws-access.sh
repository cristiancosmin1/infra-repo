#!/usr/bin/env bash

set -euo pipefail

AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-691862618786}"
AWS_REGION="${AWS_REGION:-eu-central-1}"

GITHUB_ORG="${GITHUB_ORG:-cristiancosmin1}"
GITHUB_REPO="${GITHUB_REPO:-app-repo}"

OIDC_URL="https://token.actions.githubusercontent.com"
OIDC_HOST="token.actions.githubusercontent.com"

ROLE_NAME="devops-levelup-github-actions"
POLICY_NAME="devops-levelup-github-actions"

K8S_GROUP="github-actions"
K8S_USERNAME="github-actions"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

TRUST_POLICY="${SCRIPT_DIR}/aws/github-actions-trust-policy.json"
IAM_POLICY="${SCRIPT_DIR}/aws/github-actions-policy.json"
RBAC_FILE="${REPO_ROOT}/platform/github-actions/rbac.yaml"

echo
echo "=========================================="
echo "Configuring GitHub Actions AWS/EKS access"
echo "=========================================="

# ------------------------------------------------------------
# 1. GitHub OIDC provider
# ------------------------------------------------------------

echo
echo "Checking GitHub OIDC provider..."

OIDC_ARN="$(
    aws iam list-open-id-connect-providers \
        --query 'OpenIDConnectProviderList[].Arn' \
        --output text \
    | tr '\t' '\n' \
    | grep "${OIDC_HOST}" \
    | head -n1 \
    || true
)"

if [[ -z "${OIDC_ARN}" ]]; then
    echo "Creating GitHub OIDC provider..."

    OIDC_ARN="$(
        aws iam create-open-id-connect-provider \
            --url "${OIDC_URL}" \
            --client-id-list sts.amazonaws.com \
            --query 'OpenIDConnectProviderArn' \
            --output text
    )"

    echo "OK: GitHub OIDC provider created."
else
    echo "OK: GitHub OIDC provider already exists."
fi

echo "OIDC provider: ${OIDC_ARN}"

# ------------------------------------------------------------
# 2. IAM role
# ------------------------------------------------------------

echo
echo "Checking GitHub Actions IAM role..."

if aws iam get-role \
    --role-name "${ROLE_NAME}" \
    >/dev/null 2>&1; then

    echo "OK: IAM role already exists."

    echo "Updating trust policy..."

    aws iam update-assume-role-policy \
        --role-name "${ROLE_NAME}" \
        --policy-document "file://${TRUST_POLICY}"

else
    echo "Creating IAM role..."

    aws iam create-role \
        --role-name "${ROLE_NAME}" \
        --assume-role-policy-document "file://${TRUST_POLICY}" \
        >/dev/null

    echo "OK: IAM role created."
fi

ROLE_ARN="$(
    aws iam get-role \
        --role-name "${ROLE_NAME}" \
        --query 'Role.Arn' \
        --output text
)"

echo "IAM role: ${ROLE_ARN}"

# ------------------------------------------------------------
# 3. IAM policy
# ------------------------------------------------------------

echo
echo "Checking GitHub Actions IAM policy..."

POLICY_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:policy/${POLICY_NAME}"

if aws iam get-policy \
    --policy-arn "${POLICY_ARN}" \
    >/dev/null 2>&1; then

    echo "OK: IAM policy already exists."

else
    echo "Creating IAM policy..."

    aws iam create-policy \
        --policy-name "${POLICY_NAME}" \
        --policy-document "file://${IAM_POLICY}" \
        >/dev/null

    echo "OK: IAM policy created."
fi

echo "Attaching IAM policy to role..."

aws iam attach-role-policy \
    --role-name "${ROLE_NAME}" \
    --policy-arn "${POLICY_ARN}"

echo "OK: IAM policy attached."

# ------------------------------------------------------------
# 4. Wait for aws-auth
# ------------------------------------------------------------

echo
echo "Waiting for EKS aws-auth ConfigMap..."

for _ in {1..60}; do
    if kubectl get configmap aws-auth \
        -n kube-system \
        >/dev/null 2>&1; then

        echo "OK: aws-auth exists."
        break
    fi

    sleep 5
done

if ! kubectl get configmap aws-auth \
    -n kube-system \
    >/dev/null 2>&1; then

    echo "ERROR: aws-auth ConfigMap was not found."
    exit 1
fi

# ------------------------------------------------------------
# 5. Add GitHub Actions role to aws-auth
# ------------------------------------------------------------

echo
echo "Checking GitHub Actions aws-auth mapping..."

CURRENT_MAP="$(
    kubectl get configmap aws-auth \
        -n kube-system \
        -o jsonpath='{.data.mapRoles}'
)"

if grep -Fq "${ROLE_ARN}" <<< "${CURRENT_MAP}"; then
    echo "OK: GitHub Actions role already mapped."

else
    echo "Adding GitHub Actions role to aws-auth..."

    UPDATED_MAP="$(
        printf '%s\n' "${CURRENT_MAP}"
        cat <<EOF

- rolearn: ${ROLE_ARN}
  groups:
    - ${K8S_GROUP}
  username: ${K8S_USERNAME}
EOF
    )"

    PATCH="$(
        jq -n \
            --arg mapRoles "${UPDATED_MAP}" \
            '{
                data: {
                    mapRoles: $mapRoles
                }
            }'
    )"

    kubectl patch configmap aws-auth \
        -n kube-system \
        --type merge \
        -p "${PATCH}"

    echo "OK: GitHub Actions role mapped."
fi

# ------------------------------------------------------------
# 6. Kubernetes RBAC
# ------------------------------------------------------------

echo
echo "Applying GitHub Actions Kubernetes RBAC..."

kubectl apply \
    -f "${RBAC_FILE}"

echo "OK: Kubernetes RBAC configured."

# ------------------------------------------------------------
# 7. Verify mapping
# ------------------------------------------------------------

echo
echo "Verifying GitHub Actions Kubernetes permissions..."

CAN_GET_DEPLOYMENTS="$(
    kubectl auth can-i get deployments \
        -n shopping \
        --as="${K8S_USERNAME}" \
        --as-group="${K8S_GROUP}" \
        || true
)"

if [[ "${CAN_GET_DEPLOYMENTS}" != "yes" ]]; then
    echo "ERROR: GitHub Actions cannot read deployments."
    exit 1
fi

CAN_DELETE_DEPLOYMENTS="$(
    kubectl auth can-i delete deployments \
        -n shopping \
        --as="${K8S_USERNAME}" \
        --as-group="${K8S_GROUP}" \
        || true
)"

if [[ "${CAN_DELETE_DEPLOYMENTS}" == "yes" ]]; then
    echo "ERROR: GitHub Actions unexpectedly has delete permission."
    exit 1
fi

echo "OK: GitHub Actions can read deployments."
echo "OK: GitHub Actions cannot delete deployments."

echo
echo "=========================================="
echo "GitHub Actions AWS/EKS access configured"
echo "=========================================="
echo
echo "Role:"
echo "${ROLE_ARN}"
echo
echo "Kubernetes group:"
echo "${K8S_GROUP}"
