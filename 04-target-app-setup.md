# 04 - Target Vulnerable App Setup

You need a **deliberately vulnerable web app** as the target. You do NOT build it yourself — these are ready-made, industry-standard training apps you run in Docker on the target EC2.

> These apps are intentionally insecure **by design**, for security training. Only ever run them on an isolated, self-owned target (never expose real data or a real app).

---

## Recommended: DVWA (Damn Vulnerable Web App)

Best fit for the 5 planned attacks (SQLi, XSS, brute-force all have dedicated pages, with a difficulty slider).

### Run it (on the target EC2, after installing Docker)
```bash
# install Docker (Amazon Linux 2023)
sudo dnf install -y docker
sudo systemctl enable --now docker

# run DVWA on port 80
sudo docker run -d --restart unless-stopped -p 80:80 vulnerables/web-dvwa
```

### First-time setup
1. Browse to `http://<target-or-ALB-DNS>/`
2. Login: **admin / password**
3. Click **Create / Reset Database**
4. Go to **DVWA Security** → set level to **Low** (so payloads clearly work and WAF clearly catches them)

### Where each attack goes in DVWA
| Attack | DVWA page |
|--------|-----------|
| SQL Injection | "SQL Injection" |
| XSS | "XSS (Reflected)" / "XSS (Stored)" |
| Brute force | "Brute Force" login page |
| Command injection (bonus) | "Command Injection" |

---

## Alternative: OWASP Juice Shop (broader OWASP Top 10)

More modern, more vulnerability types, gamified challenges.
```bash
sudo docker run -d --restart unless-stopped -p 80:3000 bkimminich/juice-shop
```
Browse to `http://<target-or-ALB-DNS>/`. Good if you want to explore beyond the 5 core attacks.

---

## The "sensitive data" file for Macie (separate from the app)

Macie scans **S3**, not the app. So you seed an S3 bucket with **fake** PII so Macie has something to flag.

Create a dummy CSV (all fake data) and upload it:
```bash
cat > fake-pii.csv << 'EOF'
name,email,credit_card,ssn
John Doe,john.doe@example.com,4111111111111111,123-45-6789
Jane Smith,jane.smith@example.com,5500005555555559,987-65-4321
Ahmad Ali,ahmad.ali@example.com,340000000000009,555-11-2222
EOF

aws s3 cp fake-pii.csv s3://<your-lab-macie-bucket>/
```
> These are **fake/test** numbers (standard test card numbers, invented SSNs). Never use real PII.

Macie will scan the bucket and flag it as containing sensitive data (credit cards, SSNs) — that's your Macie evidence.

---

## How the app fits the architecture

```
Kali (attacker) --internet--> WAF --> ALB --> Target EC2 [ Docker: DVWA ] :80
                                                          |
                                          S3 bucket (fake PII) <-- Macie scans
```

- The **app runs in Docker on the target EC2** on port 80.
- The **ALB** forwards internet traffic to the target on port 80.
- **WAF** (on the ALB) inspects/blocks the malicious payloads.
- **Inspector** scans the target EC2 host for CVEs.
- **Macie** scans the S3 bucket (independent of the app).

---

## Summary

- **Yes, you need a target app** — but it's a ready-made vulnerable app, not custom code.
- **Recommended: DVWA** (one Docker command, matches all 5 attacks, difficulty slider).
- **Alternative: OWASP Juice Shop** (broader OWASP coverage).
- **For Macie:** seed an S3 bucket with a fake-PII CSV (separate from the app).
