# Gemini Daily Digest Mailer

Calls the Gemini API every night, gets the top 15 viral/trending stories
(YouTube creators, tech, viral content, India news), and emails it to you
via SNS. Runs on AWS Lambda — no Docker needed.

## Flow
```
EventBridge Scheduler (cron, daily)
        |
        v
   Lambda function --> Gemini API (generateContent)
        |
        v
   SNS topic --> your email
```

## 1. Get a Gemini API key
Go to https://aistudio.google.com/apikey, sign in, create a key. Free tier
is plenty for one request a day.

## 2. Configure
Edit `deploy/config.sh`:
- `GEMINI_API_KEY` — paste your key
- `ALERT_EMAIL` — your email
- `SCHEDULE_EXPRESSION` — already set to `cron(30 17 * * ? *)` = 17:30 UTC =
  **11:00 PM IST**. Change if you want a different time (cron is always UTC).

## 3. Deploy
```bash
cd deploy
bash deploy.sh
```
Confirm the SNS subscription email when it arrives.

## 4. Test immediately
```bash
bash run_once.sh
```
Check your email after ~30-60 seconds.

## Updating the prompt later
Edit `PROMPT_TEMPLATE` in `lambda/digest_mailer.py`, then redeploy:
```bash
bash deploy/deploy.sh
```

## Cost
One Gemini Flash call/day is free-tier territory (well under the 250+
requests/day free allowance). Lambda: a few seconds of 256MB compute once a
day ≈ free tier covers this indefinitely. SNS: free under 1,000 emails/month.
Realistically **$0/month**.

## Cleanup
```bash
bash deploy/cleanup.sh
```

## Connecting to GitHub (auto-deploy on push)

Right now, deploying means running `bash deploy.sh` by hand. To make pushes
to GitHub automatically update the live Lambda code instead:

### 1. One-time: deploy manually once
You need the Lambda, IAM roles, SNS topic, and schedule to already exist
(do this once with `bash deploy/deploy.sh` as described above). GitHub
Actions will only update the *code* from then on — it won't recreate the
whole stack.

### 2. Push this project to a GitHub repo
```bash
git init
git add .
git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/YOUR_REPO.git
git push -u origin main
```
`config.sh` (which has your real Gemini key) is excluded by `.gitignore` —
only `config.example.sh` (the placeholder template) gets committed.

### 3. Add GitHub Secrets
On GitHub: your repo → **Settings** → **Secrets and variables** → **Actions**
→ **New repository secret**. Add:
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `GEMINI_API_KEY`

(Use a dedicated IAM user with only `lambda:UpdateFunctionCode`,
`lambda:UpdateFunctionConfiguration`, and `sns:ListTopics` permissions on
this function, rather than reusing your admin keys, if you want this
tighter. Not required to get it working.)

### 4. That's it
`.github/workflows/deploy.yml` is already in this project. From now on,
any push to `main` that touches `lambda/digest_mailer.py` automatically:
1. Zips the function
2. Updates the live Lambda code
3. Re-syncs the Gemini key from GitHub Secrets

The EventBridge schedule always invokes the function's `$LATEST` version,
so tonight's run uses whatever you pushed today — no extra step needed to
"point" the schedule at new code, unlike the ECS project.

You can also trigger a deploy manually from GitHub's **Actions** tab using
the "Run workflow" button (this is the `workflow_dispatch` trigger).
