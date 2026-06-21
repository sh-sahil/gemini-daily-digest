#!/usr/bin/env bash
# cleanup.sh - deletes everything deploy.sh created for the digest mailer
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "This will delete: the schedule, the Lambda function, both IAM roles, and the SNS topic."
read -p "Type 'yes' to continue: " CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 0; }

aws scheduler delete-schedule --name "$SCHEDULE_NAME" --region "$AWS_REGION" 2>/dev/null || true
aws lambda delete-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" 2>/dev/null || true

aws iam delete-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-name "digest-sns-publish" 2>/dev/null || true
aws iam detach-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole 2>/dev/null || true
aws iam delete-role --role-name "$LAMBDA_ROLE_NAME" 2>/dev/null || true

aws iam delete-role-policy --role-name "$SCHEDULER_ROLE_NAME" --policy-name "invoke-digest-lambda" 2>/dev/null || true
aws iam delete-role --role-name "$SCHEDULER_ROLE_NAME" 2>/dev/null || true

SNS_TOPIC_ARN="arn:aws:sns:${AWS_REGION}:${AWS_ACCOUNT_ID}:${SNS_TOPIC_NAME}"
aws sns delete-topic --topic-arn "$SNS_TOPIC_ARN" --region "$AWS_REGION" 2>/dev/null || true

aws logs delete-log-group --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" 2>/dev/null || true

echo "Cleanup complete."
