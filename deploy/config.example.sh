#!/usr/bin/env bash
# config.sh - edit these, then run deploy.sh

export AWS_REGION="us-east-1"

# --- Gemini ---
export GEMINI_API_KEY="PASTE-YOUR-GEMINI-API-KEY-HERE"
export GEMINI_MODEL="gemini-2.5-flash"

# --- SNS (email) ---
export SNS_TOPIC_NAME="daily-digest-alerts"
export ALERT_EMAIL="you@example.com"

# --- Lambda ---
export LAMBDA_FUNCTION_NAME="gemini-daily-digest"
export LAMBDA_ROLE_NAME="gemini-daily-digest-role"
export LAMBDA_TIMEOUT="90"      # seconds - Gemini can take a while for a long response
export LAMBDA_MEMORY="256"      # MB

# --- EventBridge Scheduler ---
export SCHEDULE_NAME="gemini-daily-digest-schedule"
export SCHEDULER_ROLE_NAME="gemini-daily-digest-scheduler-role"
# 11:00 PM IST = 17:30 UTC. Cron is always UTC.
export SCHEDULE_EXPRESSION="cron(30 17 * * ? *)"
