"""
digest_mailer.py

AWS Lambda handler. On each invocation it:
  1. Calls the Gemini API for a 15-item "what happened today" digest
     (YouTube creators, tech industry, viral content, India news)
  2. Publishes the result to SNS, which emails it to you

Uses only the Python standard library + boto3 (already included in the
Lambda runtime), so no dependency packaging/layers are needed — just zip
this one file.

Required environment variables (set on the Lambda function):
  GEMINI_API_KEY   - your Gemini API key (from Google AI Studio)
  SNS_TOPIC_ARN    - topic to publish the digest to
Optional:
  GEMINI_MODEL     - default: gemini-2.5-flash
  AWS_REGION       - set automatically by Lambda
"""
import os
import json
import urllib.request
import urllib.error
from datetime import datetime, timezone

GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-flash-lite-latest")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

GEMINI_URL = (
    f"https://generativelanguage.googleapis.com/v1beta/models/"
    f"{GEMINI_MODEL}:generateContent"
)

PROMPT_TEMPLATE = """You are my personal AI & Tech news editor.

Today's date is {date}.

Find the 15 biggest stories from the last 24 hours.

Focus on:

* AI (OpenAI, Anthropic, Google, xAI, Meta, Microsoft, Nvidia, Apple)
* AI models, research, benchmarks, startups
* Tech industry
* Product launches
* Cybersecurity
* India tech & startups
* Interesting internet stories only if they went massively viral

For every story use this format:

1. Short headline (max 10 words)

2-3 sentence summary (40-60 words):

* What happened?
* Why should I care?
* What makes it interesting?

Keep the tone:

* Fast
* Crisp
* Insightful
* Slightly witty
* Like Morning Brew or TLDR Newsletter
* No fluff
* No corporate language

Rules:

* Exactly 15 stories.
* Rank by importance.
* Prefer AI and tech over everything else.
* Skip politics, sports, celebrity gossip, and crime unless they directly affect AI or technology.
* Include numbers when relevant.
* If information is unconfirmed, clearly say so.
* Plain text only.
* No markdown.
* No long introductions or conclusions.
* Each story should take less than 30 seconds to read.
  """



def call_gemini(prompt: str) -> str:
    body = json.dumps({"contents": [{"parts": [{"text": prompt}]}]}).encode("utf-8")
    req = urllib.request.Request(
        GEMINI_URL,
        data=body,
        headers={
            "Content-Type": "application/json",
            "x-goog-api-key": GEMINI_API_KEY,
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as resp:
            data = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        raise RuntimeError(f"Gemini API error {e.code}: {err_body}") from e

    candidates = data.get("candidates", [])
    if not candidates:
        raise RuntimeError(f"No candidates in Gemini response: {data}")
    parts = candidates[0]["content"]["parts"]
    return "".join(p.get("text", "") for p in parts).strip()


def handler(event, context):
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY environment variable is not set")
    if not SNS_TOPIC_ARN:
        raise RuntimeError("SNS_TOPIC_ARN environment variable is not set")

    today = datetime.now(timezone.utc).strftime("%B %d, %Y")
    prompt = PROMPT_TEMPLATE.format(date=today)

    digest_text = call_gemini(prompt)

    import boto3

    sns = boto3.client("sns", region_name=AWS_REGION)
    subject = f"Daily Digest - {today}"[:100]  # SNS subject hard limit is 100 chars
    sns.publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=digest_text)

    return {"statusCode": 200, "body": "Digest sent"}


if __name__ == "__main__":
    # Local test: prints the digest instead of publishing to SNS.
    # Run with: GEMINI_API_KEY=xxx python3 digest_mailer.py
    if not GEMINI_API_KEY:
        print("Set GEMINI_API_KEY to test locally.")
    else:
        today = datetime.now(timezone.utc).strftime("%B %d, %Y")
        print(call_gemini(PROMPT_TEMPLATE.format(date=today)))
