#!/usr/bin/env bash
# run_once.sh - manually invoke the digest Lambda right now and show the result
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

aws lambda invoke \
  --function-name "$LAMBDA_FUNCTION_NAME" \
  --region "$AWS_REGION" \
  --cli-read-timeout 120 \
  "$SCRIPT_DIR/invoke-output.json" > /dev/null

echo "Response:"
cat "$SCRIPT_DIR/invoke-output.json"
echo ""
echo ""
echo "If you see an error above, check the logs:"
echo "  aws logs tail /aws/lambda/$LAMBDA_FUNCTION_NAME --since 5m --region $AWS_REGION"
echo ""
echo "If it succeeded, check your email for the digest (and spam folder)."
