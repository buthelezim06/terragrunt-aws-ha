#!/usr/bin/env bash
# Usage: ./deploy.sh <env> <plan|apply|destroy> [component]
#   ./deploy.sh dev plan
#   ./deploy.sh dev apply
#   ./deploy.sh dev apply ec2        # single component only
#   ./deploy.sh prod destroy
set -euo pipefail

ENV="${1:?environment required: dev|staging|uat|prod}"
ACTION="${2:?action required: plan|apply|destroy}"
COMPONENT="${3:-}"

VALID_ENVS=(dev staging uat prod)
if [[ ! " ${VALID_ENVS[*]} " =~ " ${ENV} " ]]; then
  echo "Invalid environment '${ENV}'. Must be one of: ${VALID_ENVS[*]}"
  exit 1
fi

if [[ "${ENV}" == "prod" && "${ACTION}" != "plan" ]]; then
  read -p "You are about to ${ACTION} PROD. Type 'yes' to continue: " CONFIRM
  [[ "${CONFIRM}" == "yes" ]] || { echo "Aborted."; exit 1; }
fi

cd "$(dirname "$0")/../live/${ENV}${COMPONENT:+/${COMPONENT}}"

case "${ACTION}" in
  init)    terragrunt run --all init -reconfigure ;;
  plan)    terragrunt run --all plan ;;
  apply)   terragrunt run --all apply --terragrunt-non-interactive ;;
  destroy) terragrunt run --all destroy ;;
  *) echo "Unknown action '${ACTION}'. Use plan|apply|destroy"; exit 1 ;;
esac
