#!/usr/bin/env bash
# Creates the S3 bucket + DynamoDB table Terragrunt needs for remote state.
# Run this once, before any `terragrunt apply`.
set -euo pipefail

REGION="af-south-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="acme-terraform-state-${ACCOUNT_ID}"
TABLE="terraform-locks"

echo "Account: ${ACCOUNT_ID}  Region: ${REGION}"

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "Bucket ${BUCKET} already exists, skipping."
else
  echo "Creating state bucket ${BUCKET}..."
  aws s3api create-bucket \
    --bucket "${BUCKET}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"
  aws s3api put-bucket-versioning \
    --bucket "${BUCKET}" \
    --versioning-configuration Status=Enabled
  aws s3api put-bucket-encryption \
    --bucket "${BUCKET}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
  aws s3api put-public-access-block \
    --bucket "${BUCKET}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
fi

if aws dynamodb describe-table --table-name "${TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "Lock table ${TABLE} already exists, skipping."
else
  echo "Creating lock table ${TABLE}..."
  aws dynamodb create-table \
    --table-name "${TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST \
    --region "${REGION}"
fi

echo "Backend ready."
