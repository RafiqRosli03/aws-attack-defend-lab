# 02 - Attack Plan (5 attacks) + Detection Mapping

> All attacks run **from your Kali EC2 against your own target** in your sandbox account. Educational red/blue-team exercise only.

The point of each attack is twofold: (1) execute a common attack technique, and (2) **watch which AWS defense detects it** and capture the evidence.

---

## Attack summary table

| # | Attack | OWASP Top 10 | Kali tool | Primary AWS detection | Also visible in |
|---|--------|--------------|-----------|----------------------|-----------------|
| 1 | **Reconnaissance / Port scan** | A05 Security Misconfiguration (recon phase) | `nmap` | **GuardDuty** (Recon:EC2/Portscan) | VPC Flow Logs |
| 2 | **SQL Injection** | A03 Injection | `sqlmap` | **AWS WAF** (SQLi managed rule blocks it) | Security Hub |
| 3 | **Cross-Site Scripting (XSS)** | A03 Injection | Burp / manual / `xsser` | **AWS WAF** (XSS managed rule) | Security Hub |
| 4 | **Brute-force login** | A07 Identification & Auth Failures | `hydra` | **WAF rate-based rule** + **GuardDuty** | ALB logs |
| 5 | **Vulnerability scan** | A06 Vulnerable & Outdated Components | `nikto` (web) + **Inspector** (host CVEs) | **Inspector** (EC2 CVE findings) + WAF (scanner signatures) | Security Hub |

All findings roll up into **Security Hub**, and the attacker's behavior can be visualized in **Detective**.

---

## Detailed attack steps

### Attack 1 - Reconnaissance / Port scan (→ GuardDuty)
- **Goal:** map open ports on the target, trigger threat detection.
- **Command (example):**
  ```bash
  nmap -sS -sV -p- <target-alb-or-ec2-ip>
  ```
- **What detects it:** **GuardDuty** flags port scanning from the attacker IP (finding type like `Recon:EC2/PortProbeUnprotectedPort` or portscan). VPC Flow Logs record the sweep.
- **Screenshot:** GuardDuty finding + the nmap output.

### Attack 2 - SQL Injection (→ WAF)
- **Goal:** exploit the app's login/search field with SQLi.
- **Command (example):**
  ```bash
  sqlmap -u "http://<target>/vulnerabilities/sqli/?id=1&Submit=Submit" --cookie="..." --batch --dbs
  ```
- **What detects it:** **AWS WAF** SQLi managed rule blocks/counts the malicious payloads at the ALB.
- **Screenshot:** WAF sampled requests filtered to BLOCK showing the SQLi rule + sqlmap being blocked.

### Attack 3 - Cross-Site Scripting / XSS (→ WAF)
- **Goal:** inject a script payload into an input field.
- **Payload (example):**
  ```
  <script>alert('xss')</script>
  ```
  (submit via the app's reflected/stored XSS page, or via Burp Repeater)
- **What detects it:** **AWS WAF** XSS managed rule.
- **Screenshot:** WAF blocked XSS request in sampled requests.

### Attack 4 - Brute-force login (→ WAF rate rule + GuardDuty)
- **Goal:** hammer the login form with many credential attempts.
- **Command (example):**
  ```bash
  hydra -l admin -P /usr/share/wordlists/rockyou.txt <target> http-post-form "/login:username=^USER^&password=^PASS^:F=incorrect"
  ```
- **What detects it:** **WAF rate-based rule** (block after N requests/5 min) + GuardDuty may flag the volume.
- **Screenshot:** WAF rate-rule blocks + hydra getting throttled.

### Attack 5 - Vulnerability scan (→ Inspector + WAF)
- **Goal:** scan the web app and the host for known vulnerabilities.
- **Commands (example):**
  ```bash
  nikto -h http://<target>
  ```
  Meanwhile **Amazon Inspector** (agent/agentless) scans the **target EC2** for OS/package CVEs.
- **What detects it:** **Inspector** produces CVE findings on the target instance; WAF flags the scanner signatures.
- **Screenshot:** Inspector findings list (CVEs) + Security Hub aggregation.

---

## Recommended execution order (1-day flow)

1. **Morning setup:** deploy both environments, enable all security services, wait ~30-60 min so GuardDuty/Inspector baseline.
2. **Run attacks in order 1 → 5**, pausing after each to let detections appear (findings can take a few minutes).
3. **Collect evidence** after each attack (findings often take 5-15 min to surface).
4. **Investigate in Detective** — view the attacker IP's behavior graph.
5. **Review Security Hub** — see everything aggregated + the security score.
6. **Tear down** (see `03-cost-and-teardown.md`).

---

## Evidence checklist (for your documentation)

- [ ] nmap output + GuardDuty portscan finding
- [ ] sqlmap blocked + WAF SQLi sampled request
- [ ] XSS payload blocked + WAF XSS sampled request
- [ ] hydra throttled + WAF rate-rule counter
- [ ] nikto output + Inspector CVE findings
- [ ] Detective investigation graph of attacker IP
- [ ] Security Hub summary (all findings + score)
- [ ] Macie finding on the fake-PII S3 bucket
- [ ] CloudTrail showing the API activity timeline

---

## Notes / expectations

- **Findings take time.** GuardDuty and Inspector are not instant — allow 5-30 min. Plan the day around waiting periods.
- **WAF is the fastest feedback** — blocks show almost immediately in sampled requests.
- **Macie** is independent of the attacks — it scans the S3 bucket you seed with fake PII; run it once to show sensitive-data detection.
- **Inspector** needs the SSM agent on the target EC2 (agent-based) or uses agentless scanning — confirm in build.
