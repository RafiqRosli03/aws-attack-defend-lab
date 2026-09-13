# GuardDuty Findings

**Service:** Amazon GuardDuty (threat detection)  |  **Region:** ap-southeast-5

GuardDuty raised **2 findings**, both pointing at the Kali attacker instance (`i-05af06e7d86405127`).

## Findings

| Severity | Type | Detail |
|----------|------|--------|
| **8.0 HIGH** | `Execution:EC2/MaliciousFile` | 1,794 malicious files detected (incl. Adware.GenericKD.61062072) — the Kali pentest toolset |
| **5.0 MEDIUM** | `Recon:EC2/Portscan` | Outbound port scan detected (the nmap recon from Attack 1) |

## Why this matters
- The **port scan** finding proves GuardDuty caught what the **WAF could not see** (port scans are not HTTP).
- The **malicious file** finding shows GuardDuty Malware Protection scanned the instance disk — exactly how a compromised/rogue instance would be detected in the real world.
- Together they demonstrate **network + host** threat detection that complements the WAF's application-layer blocking.

Deep-dive on the malware finding: [`../Additional Findings through GuardDuty/kali-malicious-file-scan.txt`](../Additional%20Findings%20through%20GuardDuty/kali-malicious-file-scan.txt)

## Evidence
![gd 1](./Screenshot%202026-09-13%20190145.png)
![gd 2](./Screenshot%202026-09-13%20190203.png)
![gd 3](./Screenshot%202026-09-13%20191048.png)
![gd 4](./Screenshot%202026-09-13%20191136.png)
