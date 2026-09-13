# Deployment Guide - Attack & Defend Lab

Region: **ap-southeast-5 (Malaysia)** | Access: **SSM Session Manager** | App: **DVWA** | Account: **dedicated sandbox**

Run everything in order. Budget for ~1 day, then run the teardown at the end.

---

## Prerequisites

1. Logged into your **dedicated sandbox account**.
2. Region set to **ap-southeast-5**.
3. **Subscribe to the Kali Linux AMI** in AWS Marketplace (one-time, free subscription):
   - AWS Marketplace → search "Kali Linux" → Subscribe → Continue to Configuration → pick region ap-southeast-5 → copy the **AMI ID**.
4. Set a **$60 budget alert** first (Billing → Budgets).

---

## Step 1 - Deploy the infrastructure (CloudFormation)

```powershell
aws cloudformation deploy `
  --region ap-southeast-5 `
  --stack-name attack-defend-lab `
  --template-file lab-infrastructure.yaml `
  --capabilities CAPABILITY_NAMED_IAM `
  --parameter-overrides `
      KaliAmiId=ami-xxxxxxxxxxxxxxxxx `
      InstanceType=t3.small
```
Replace `ami-xxxx` with the Kali AMI ID from the Marketplace step.

Get the outputs (DVWA URL, instance IDs, bucket name):
```powershell
aws cloudformation describe-stacks --region ap-southeast-5 `
  --stack-name attack-defend-lab `
  --query "Stacks[0].Outputs" --output table
```

Wait ~3-5 min for the DVWA container to start, then open the **DvwaUrl** in a browser:
- Login: `admin` / `password`
- Click **Create / Reset Database**
- **DVWA Security** → set to **Low**

---

## Step 2 - Enable the defensive security services

These are region toggles (mostly free-trial for new accounts). Enable in **ap-southeast-5**.

```powershell
# GuardDuty
aws guardduty create-detector --enable --region ap-southeast-5

# Security Hub (aggregates findings)
aws securityhub enable-security-hub --region ap-southeast-5

# Inspector (scans EC2 for CVEs)
aws inspector2 enable --resource-types EC2 --region ap-southeast-5

# Macie
aws macie2 enable-macie --region ap-southeast-5

# Detective
aws detective create-graph --region ap-southeast-5
```

> Let them baseline for ~30-60 min before attacking (GuardDuty/Inspector need time).

---

## Step 3 - Seed the Macie bucket with fake PII

```powershell
@"
name,email,credit_card,ssn
John Doe,john.doe@example.com,4111111111111111,123-45-6789
Jane Smith,jane.smith@example.com,5500005555555559,987-65-4321
"@ | Out-File -Encoding ascii fake-pii.csv

aws s3 cp fake-pii.csv s3://lab-macie-fakepii-<ACCOUNT_ID>/
```
(Use the `MacieBucketName` from the stack outputs.) Then in Macie console → create a one-time sensitive-data discovery job on that bucket.

---

## Step 4 - Connect to Kali (SSM, no SSH)

```powershell
aws ssm start-session --target <KaliInstanceId> --region ap-southeast-5
```
Or console: **Systems Manager → Session Manager → Start session → lab-kali-attacker**.

> If Kali doesn't appear in Session Manager, wait a few minutes for the SSM agent to register, and confirm the instance has the SSM role (it does, from the template).

---

## Step 5 - Run the 5 attacks

From the Kali session, targeting the **DvwaUrl** (the ALB). See `../02-attack-plan.md` for full detail. Quick version:

```bash
TARGET="<paste DvwaUrl host, e.g. lab-dvwa-alb-xxxx.ap-southeast-5.elb.amazonaws.com>"

# 1. Recon / port scan  -> GuardDuty
nmap -sS -sV $TARGET

# 2. SQL injection       -> WAF (SQLi rule)
sqlmap -u "http://$TARGET/vulnerabilities/sqli/?id=1&Submit=Submit" --batch

# 3. XSS                 -> WAF (Common rule)  [also do via browser on the XSS page]
curl "http://$TARGET/vulnerabilities/xss_r/?name=<script>alert(1)</script>"

# 4. Brute force         -> WAF rate rule
hydra -l admin -P /usr/share/wordlists/rockyou.txt $TARGET http-post-form \
  "/login.php:username=^USER^&password=^PASS^:Login failed"

# 5. Web vuln scan       -> Inspector (host) + WAF (scanner sigs)
nikto -h http://$TARGET
```

Pause ~5-15 min after the attacks for findings to appear.

---

## Step 6 - Collect evidence (screenshots)

| Where | What to capture |
|-------|-----------------|
| **WAF** → Web ACL `lab-dvwa-webacl` → Sampled requests (filter BLOCK) | SQLi/XSS/rate blocks |
| **GuardDuty** → Findings | Port scan / recon findings |
| **Inspector** → Findings | CVEs on the target EC2 |
| **Macie** → Findings | Sensitive data (cards/SSN) in the bucket |
| **Security Hub** → Summary + Findings | Everything aggregated + score |
| **Detective** → search the attacker IP | Investigation graph |

Save screenshots into an `evidence/` folder for your documentation.

---

## Step 7 - TEAR DOWN (mandatory, same day)

Run the teardown script: see `teardown.ps1`. Do not skip this — the ALB, WAF, and EIPs bill hourly and the security services bill after the free trial.

---

## Troubleshooting

- **DVWA URL shows 502/503:** container still starting, or health check failing. Wait a few min; check target via SSM: `sudo docker ps`.
- **Kali not in Session Manager:** wait for SSM agent; confirm outbound internet (it's in a public subnet with IGW).
- **No WAF blocks:** DVWA security must be **Low**, and make sure you're hitting the **ALB URL**, not the instance directly.
- **Findings slow:** normal - GuardDuty/Inspector take minutes to tens of minutes.
