# Attack 2 — SQL Injection

**Tool:** `sqlmap`  |  **OWASP:** A03 Injection  |  **Blocked by:** AWS WAF (SQLi managed rule)

## Objective
Attempt SQL injection against the DVWA `sqli` endpoint to extract database data.

## Command
```bash
sqlmap -u "http://<DVWA-ALB-DNS>/vulnerabilities/sqli/?id=1&Submit=Submit" \
  --cookie="security=low; PHPSESSID=test" --batch --level=2
```

## Result — BLOCKED by AWS WAF
- sqlmap reported: **`WAF/IPS identified as 'AWS WAF (Amazon)'`**
- Every injection payload returned **HTTP 403 Forbidden**
- Final tally: **`403 (Forbidden) - 1503 times`**
- sqlmap concluded: *"all tested parameters do not appear to be injectable"* and suggested `--tamper` to evade the WAF
- **Outcome:** the SQL injection was fully blocked at the edge — payloads never reached DVWA.

## Detection / Defense
- **AWS WAF `AWSManagedRulesSQLiRuleSet`** detected and blocked the injection signatures.
- This is application-layer defense working exactly as intended.

## Evidence

### Attack surface (sqlmap running from Kali)
![sqlmap 1](./Attack%20Surface/Screenshot%202026-09-13%20172810.png)
![sqlmap 2](./Attack%20Surface/Screenshot%202026-09-13%20172821.png)
![sqlmap 3](./Attack%20Surface/Screenshot%202026-09-13%20172831.png)
![sqlmap 4](./Attack%20Surface/Screenshot%202026-09-13%20172838.png)
![sqlmap 5](./Attack%20Surface/Screenshot%202026-09-13%20172848.png)
![sqlmap 6](./Attack%20Surface/Screenshot%202026-09-13%20172857.png)
![sqlmap 7](./Attack%20Surface/Screenshot%202026-09-13%20172908.png)
![sqlmap 8](./Attack%20Surface/Screenshot%202026-09-13%20172917.png)

### Logs / WAF blocks (403 x 1503)
![log 1](./Logs/Screenshot%202026-09-13%20173208.png)
![log 2](./Logs/Screenshot%202026-09-13%20173228.png)
![log 3](./Logs/Screenshot%202026-09-13%20173322.png)
![log 4](./Logs/Screenshot%202026-09-13%20173421.png)
![log 5](./Logs/Screenshot%202026-09-13%20173517.png)
![log 6](./Logs/Screenshot%202026-09-13%20173640.png)
![log 7](./Logs/Screenshot%202026-09-13%20173754.png)
![log 8](./Logs/Screenshot%202026-09-13%20173947.png)
