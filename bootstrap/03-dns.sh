#!/usr/bin/env bash

set -euo pipefail

ZONE_ID="Z04836331XFINI3550HF4"
DOMAIN="cdevops-levelup.ro"
REGION="eu-central-1"

echo "========================================"
echo "Route53 post-bootstrap configuration"
echo "========================================"

echo "Waiting for ingress-nginx LoadBalancer..."

LB_HOST=""

until [[ -n "$LB_HOST" ]]; do
  LB_HOST="$(
    kubectl get svc ingress-nginx-controller \
      -n ingress-nginx \
      -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' \
      2>/dev/null || true
  )"

  if [[ -z "$LB_HOST" ]]; then
    echo "LoadBalancer not ready yet. Retrying in 10 seconds..."
    sleep 10
  fi
done

echo "LoadBalancer DNS:"
echo "$LB_HOST"

echo
echo "Detecting AWS Load Balancer hosted zone..."

LB_ZONE_ID="$(
  aws elb describe-load-balancers \
    --region "$REGION" \
    --query "LoadBalancerDescriptions[?DNSName=='${LB_HOST}'].CanonicalHostedZoneNameID | [0]" \
    --output text
)"

if [[ -z "$LB_ZONE_ID" || "$LB_ZONE_ID" == "None" ]]; then
  echo "ERROR: Could not determine the Classic ELB hosted zone ID."
  exit 1
fi

echo "LoadBalancer Zone ID:"
echo "$LB_ZONE_ID"

echo
echo "Updating Route53 records..."

cat >/tmp/route53-change.json <<EOF
{
  "Changes": [
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "app.${DOMAIN}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${LB_ZONE_ID}",
          "DNSName": "${LB_HOST}",
          "EvaluateTargetHealth": false
        }
      }
    },
    {
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "auth.${DOMAIN}",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "${LB_ZONE_ID}",
          "DNSName": "${LB_HOST}",
          "EvaluateTargetHealth": false
        }
      }
    }
  ]
}
EOF

CHANGE_ID="$(
  aws route53 change-resource-record-sets \
    --hosted-zone-id "$ZONE_ID" \
    --change-batch file:///tmp/route53-change.json \
    --query 'ChangeInfo.Id' \
    --output text
)"

echo "Route53 change submitted:"
echo "$CHANGE_ID"

echo
echo "Waiting for Route53 change to become INSYNC..."

aws route53 wait resource-record-sets-changed \
  --id "$CHANGE_ID"

echo "Route53 change is INSYNC."

echo
echo "========================================"
echo "Route53 records"
echo "========================================"

aws route53 list-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --query "ResourceRecordSets[?Name=='app.${DOMAIN}.' || Name=='auth.${DOMAIN}.'].{Name:Name,Target:AliasTarget.DNSName}" \
  --output table

echo
echo "DNS bootstrap completed successfully."
