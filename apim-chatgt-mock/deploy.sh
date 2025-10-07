#!/usr/bin/env bash
set -euo pipefail

# ---- Config you can override or pass via terraform.tfvars ----
SUBSCRIPTION_ID="${SUBSCRIPTION_ID:-}"   # If blank, script will prompt
TF_VAR_FILE="${TF_VAR_FILE:-terraform.tfvars}"

# ---- Azure Login ----
echo ">> Logging into Azure..."
if ! az account show >/dev/null 2>&1; then
  az login --use-device-code
fi

if [[ -z "${SUBSCRIPTION_ID}" ]]; then
  echo ">> Available subscriptions:"
  az account list --query '[].{name:name, id:id}' -o table
  read -r -p "Enter Subscription ID to use: " SUBSCRIPTION_ID
fi

echo ">> Setting subscription: ${SUBSCRIPTION_ID}"
az account set --subscription "${SUBSCRIPTION_ID}"

# ---- Terraform ----
echo ">> Terraform init"
terraform init

echo ">> Terraform validate"
terraform validate

# Ensure subscription_id is provided to Terraform (via var file or env)
if ! grep -q 'subscription_id' "${TF_VAR_FILE}" 2>/dev/null && [[ -z "${TF_VAR_subscription_id:-}" ]]; then
  echo "subscription_id = \"${SUBSCRIPTION_ID}\"" >> "${TF_VAR_FILE}"
  echo ">> Wrote subscription_id to ${TF_VAR_FILE}"
fi

echo ">> Terraform plan"
terraform plan -out tfplan

echo ">> Terraform apply"
terraform apply -auto-approve tfplan

echo ">> Done."
echo "Useful outputs:"
terraform output

# Quick test with curl
APIM_URL=$(terraform output -raw mock_chat_completions_url 2>/dev/null || true)
if [[ -n "${APIM_URL}" ]]; then
  echo
  echo ">> Testing the mocked endpoint with curl:"
  echo "curl -s -X POST \"${APIM_URL}\" -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"Say hi\"}]}' | jq ."
  echo
fi
