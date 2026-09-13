# Attack 3 — Cross-Site Scripting (XSS)

**Tool:** `curl` payloads  |  **OWASP:** A03 Injection  |  **Blocked by:** AWS WAF (Common rule set)

## Objective
Inject `<script>` / event-handler payloads into DVWA input fields to trigger XSS.

## Commands
```bash
curl -i "http://<DVWA-ALB-DNS>/vulnerabilities/xss_r/?name=<script>alert(1)</script>" \
  --cookie "security=low; PHPSESSID=test"

# burst of 15 to make the WAF blocks obvious
for i in $(seq 1 15); do
  curl -s -o /dev/null -w "HTTP %{http_code}\n" \
    "http://<DVWA-ALB-DNS>/vulnerabilities/xss_r/?name=<script>alert($i)</script>" \
    --cookie "security=low; PHPSESSID=test"
done
```

## Result — BLOCKED by AWS WAF
- XSS payloads returned **HTTP 403 Forbidden**
- The `<script>` and `onerror=` signatures were caught by the WAF **Core/Common rule set**
- Payloads never reached DVWA — no alert popup, no reflected script

## Detection / Defense
- **AWS WAF `AWSManagedRulesCommonRuleSet`** detected and blocked the XSS signatures.
- Application-layer defense working as intended.

## Evidence

### Attack surface (XSS payloads from Kali)
![xss attack](./Attack%20surface/Screenshot%202026-09-13%20174618.png)

### Logs / WAF blocks
![log 1](./Logs/Screenshot%202026-09-13%20174739.png)
![log 2](./Logs/Screenshot%202026-09-13%20174752.png)
![log 3](./Logs/Screenshot%202026-09-13%20174806.png)
![log 4](./Logs/Screenshot%202026-09-13%20174819.png)
![log 5](./Logs/Screenshot%202026-09-13%20174936.png)
![log 6](./Logs/Screenshot%202026-09-13%20175012.png)
