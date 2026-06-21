#!/usr/bin/env bash
# deploy.sh
# Run from the deploy/ directory: bash deploy.sh
# Safe to re-run after editing config.sh or the Lambda code.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
source "$SCRIPT_DIR/config.sh"

echo "=== Checking prerequisites ==="
command -v aws >/dev/null || { echo "AWS CLI not found. Install it first."; exit 1; }
aws sts get-caller-identity >/dev/null || { echo "AWS CLI not configured. Run 'aws configure' first."; exit 1; }
if [ "$GEMINI_API_KEY" = "PASTE-YOUR-GEMINI-API-KEY-HERE" ]; then
  echo "ERROR: set GEMINI_API_KEY in config.sh first (get one at https://aistudio.google.com/apikey)"
  exit 1
fi

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account: $AWS_ACCOUNT_ID  Region: $AWS_REGION"

# ---------------------------------------------------------------------------
echo ""
echo "=== Step 1/5: SNS topic + email subscription ==="
SNS_TOPIC_ARN=$(aws sns create-topic --name "$SNS_TOPIC_NAME" --region "$AWS_REGION" --query TopicArn --output text)
aws sns subscribe --topic-arn "$SNS_TOPIC_ARN" --protocol email --notification-endpoint "$ALERT_EMAIL" --region "$AWS_REGION" >/dev/null
echo "Topic: $SNS_TOPIC_ARN"
echo ">>> Check $ALERT_EMAIL and CONFIRM the subscription if you haven't already. <<<"

# ---------------------------------------------------------------------------
echo ""
echo "=== Step 2/5: IAM role for Lambda ==="
if ! aws iam get-role --role-name "$LAMBDA_ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$LAMBDA_ROLE_NAME" --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }' >/dev/null
  aws iam attach-role-policy --role-name "$LAMBDA_ROLE_NAME" \
    --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole
  echo "Created $LAMBDA_ROLE_NAME"
  echo "Waiting for IAM role to propagate..."
  sleep 10
else
  echo "$LAMBDA_ROLE_NAME already exists"
fi
aws iam put-role-policy --role-name "$LAMBDA_ROLE_NAME" --policy-name "digest-sns-publish" --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{"Effect": "Allow", "Action": "sns:Publish", "Resource": "'"$SNS_TOPIC_ARN"'"}]
}'
LAMBDA_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${LAMBDA_ROLE_NAME}"

# ---------------------------------------------------------------------------
echo ""
echo "=== Step 3/5: Package and deploy Lambda function ==="
rm -f "$SCRIPT_DIR/function.zip"
( cd "$PROJECT_ROOT/lambda" && zip -q "$SCRIPT_DIR/function.zip" digest_mailer.py )

ENV_VARS="Variables={GEMINI_API_KEY=$GEMINI_API_KEY,GEMINI_MODEL=$GEMINI_MODEL,SNS_TOPIC_ARN=$SNS_TOPIC_ARN}"

if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws lambda update-function-code \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --zip-file "fileb://$SCRIPT_DIR/function.zip" \
    --region "$AWS_REGION" >/dev/null
  aws lambda wait function-updated --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION"
  aws lambda update-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --timeout "$LAMBDA_TIMEOUT" \
    --memory-size "$LAMBDA_MEMORY" \
    --environment "$ENV_VARS" \
    --region "$AWS_REGION" >/dev/null
  echo "Updated existing Lambda function $LAMBDA_FUNCTION_NAME"
else
  aws lambda create-function \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --runtime python3.12 \
    --handler digest_mailer.handler \
    --role "$LAMBDA_ROLE_ARN" \
    --zip-file "fileb://$SCRIPT_DIR/function.zip" \
    --timeout "$LAMBDA_TIMEOUT" \
    --memory-size "$LAMBDA_MEMORY" \
    --environment "$ENV_VARS" \
    --region "$AWS_REGION" >/dev/null
  echo "Created Lambda function $LAMBDA_FUNCTION_NAME"
fi
LAMBDA_ARN=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --region "$AWS_REGION" --query "Configuration.FunctionArn" --output text)

# ---------------------------------------------------------------------------
echo ""
echo "=== Step 4/5: IAM role for EventBridge Scheduler ==="
if ! aws iam get-role --role-name "$SCHEDULER_ROLE_NAME" >/dev/null 2>&1; then
  aws iam create-role --role-name "$SCHEDULER_ROLE_NAME" --assume-role-policy-document '{
    "Version": "2012-10-17",
    "Statement": [{"Effect": "Allow", "Principal": {"Service": "scheduler.amazonaws.com"}, "Action": "sts:AssumeRole"}]
  }' >/dev/null
  echo "Created $SCHEDULER_ROLE_NAME"
  echo "Waiting for IAM role to propagate..."
  sleep 10
else
  echo "$SCHEDULER_ROLE_NAME already exists"
fi
aws iam put-role-policy --role-name "$SCHEDULER_ROLE_NAME" --policy-name "invoke-digest-lambda" --policy-document '{
  "Version": "2012-10-17",
  "Statement": [{"Effect": "Allow", "Action": "lambda:InvokeFunction", "Resource": "'"$LAMBDA_ARN"'"}]
}'
SCHEDULER_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${SCHEDULER_ROLE_NAME}"

# ---------------------------------------------------------------------------
echo ""
echo "=== Step 5/5: EventBridge schedule ==="
cat > "$SCRIPT_DIR/schedule-target.json" <<EOF
{
  "RoleArn": "${SCHEDULER_ROLE_ARN}",
  "Arn": "${LAMBDA_ARN}",
  "Input": "{}"
}
EOF

if aws scheduler get-schedule --name "$SCHEDULE_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  aws scheduler update-schedule --name "$SCHEDULE_NAME" --region "$AWS_REGION" \
    --schedule-expression "$SCHEDULE_EXPRESSION" \
    --flexible-time-window '{"Mode": "OFF"}' \
    --target "file://$SCRIPT_DIR/schedule-target.json" >/dev/null
  echo "Updated schedule $SCHEDULE_NAME"
else
  aws scheduler create-schedule --name "$SCHEDULE_NAME" --region "$AWS_REGION" \
    --schedule-expression "$SCHEDULE_EXPRESSION" \
    --flexible-time-window '{"Mode": "OFF"}' \
    --target "file://$SCRIPT_DIR/schedule-target.json" >/dev/null
  echo "Created schedule $SCHEDULE_NAME ($SCHEDULE_EXPRESSION, UTC)"
fi

# ---------------------------------------------------------------------------
echo ""
echo "=== Done ==="
echo "Lambda:     $LAMBDA_ARN"
echo "SNS topic:  $SNS_TOPIC_ARN  (confirm the email subscription if you haven't!)"
echo "Schedule:   $SCHEDULE_EXPRESSION (UTC) -> $SCHEDULE_NAME"
echo ""
echo "To trigger it right now without waiting for the schedule:"
echo "  bash run_once.sh"
