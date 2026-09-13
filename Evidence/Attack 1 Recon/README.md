# Attack 1 — Reconnaissance (Port & Service Scan)

**Tool:** `nmap`  |  **OWASP phase:** Reconnaissance  |  **Detected by:** Amazon GuardDuty

## Objective
Enumerate open ports/services on the target (the ALB in front of DVWA) — the first step of any attack.

## Command
```bash
nmap -sV -Pn <DVWA-ALB-DNS>
```

## Result
- **80/tcp open** → `http` (AWS Elastic Load Balancing)
- **999 ports filtered** (no response) → the security group blocks everything except 80
- Confirmed the only exposed entry point is the web port on the ALB

## Detection
- **AWS WAF did NOT see this** — port scans are not HTTP traffic, so they never reach the WAF.
- **Amazon GuardDuty** later raised `Recon:EC2/Portscan` (Medium, 5.0) for the outbound scan from the Kali instance, sourced from VPC Flow Logs.
- **Lesson:** network reconnaissance requires network-level detection (GuardDuty), not a web firewall.

## Evidence

### Attack surface (nmap from Kali)
![nmap scan](./Attack%20surface/Screenshot%202026-09-13%20171646.png)

### Logs
![log 1](./Logs/Screenshot%202026-09-13%20174301.png)
![log 2](./Logs/Screenshot%202026-09-13%20174342.png)
![log 3](./Logs/Screenshot%202026-09-13%20174356.png)
![log 4](./Logs/Screenshot%202026-09-13%20174404.png)
