# 01 - Architecture Design

## Overview

Two logical environments inside **one dedicated sandbox AWS account**, connected only over the internet (like a real external attacker reaching a public web app).

```
                          INTERNET
                             |
        +--------------------+---------------------+
        |                                          |
  ATTACKER ENV                              DEFENDER ENV (target)
  (Attacker VPC)                            (Defender VPC)
        |                                          |
  Kali Linux EC2                          AWS WAF (web ACL)
  (public IP)                                    |
                                          Application Load Balancer
                                                 |
                                          Vulnerable Web App EC2
                                          (DVWA / OWASP Juice Shop)
                                                 |
                                          S3 bucket (fake "sensitive" data for Macie)

  Account-wide detection & evidence:
    GuardDuty | Inspector | Detective | Security Hub | Macie
    CloudTrail | VPC Flow Logs
```

> Keeping attacker and target in **separate VPCs** and routing over the public internet makes the attack traffic look external — which is what makes GuardDuty and WAF light up realistically.

---

## Attacker environment

| Item | Choice | Notes |
|------|--------|-------|
| Compute | **1x EC2, `t3.small`** | 2 vCPU / 2 GB — enough for scanning tools |
| OS / AMI | **Kali Linux** (AWS Marketplace, official Kali image) | Free AMI; you pay only for the EC2 hours |
| Network | Attacker VPC, public subnet, public IP | So it can reach the target over the internet |
| Access | **SSM Session Manager** (preferred) or SSH key | SSM avoids opening port 22 to the world |
| Tools (pre-installed on Kali) | nmap, sqlmap, nikto, hydra, Burp Suite, Metasploit, curl | Standard Kali toolset |

**Security group (attacker):** outbound open (to attack), inbound only from your own IP (for SSH) or none (if using SSM).

---

## Defender / target environment

### The vulnerable web app (the target)
| Item | Choice | Notes |
|------|--------|-------|
| Compute | **1x EC2, `t3.small`** | Runs the vulnerable app in Docker |
| App | **DVWA** (Damn Vulnerable Web App) or **OWASP Juice Shop** | Purpose-built vulnerable apps for training |
| Deploy | Docker container on the EC2 | `docker run` DVWA/Juice Shop |
| Network | Defender VPC, public subnet (behind ALB) | Reachable from attacker |

### The front door + WAF
| Item | Choice | Notes |
|------|--------|-------|
| Load balancer | **Application Load Balancer (ALB)** | WAF attaches to ALB (regional WAF) |
| Firewall | **AWS WAF** web ACL on the ALB | Use AWS Managed Rules (SQLi, XSS, common rule set) |

> Note: WAF on an **ALB is regional** (in your region, e.g. ap-southeast-5) — different from CloudFront WAF which is us-east-1. For this lab, ALB + regional WAF is simplest.

### The "sensitive data" target for Macie
| Item | Choice | Notes |
|------|--------|-------|
| Storage | **1x S3 bucket** with **fake** PII (dummy names, fake card numbers, sample .csv) | Macie scans it and flags "sensitive data" |

---

## Account-wide detection & evidence services

| Service | Role in the lab | What you'll observe |
|---------|-----------------|---------------------|
| **AWS WAF** | Blocks/counts malicious web requests at the ALB | SQLi/XSS requests blocked; sampled requests |
| **GuardDuty** | Threat detection from VPC Flow Logs, DNS, CloudTrail | Port scans, recon, unusual API calls → findings |
| **Inspector** | Scans the target EC2 for CVEs / vulns | Vulnerability findings on the target instance |
| **Detective** | Builds an investigation graph of the activity | Visualize the attacker's behavior over time |
| **Security Hub** | Central console aggregating all findings | Single pane: WAF + GuardDuty + Inspector findings + compliance score |
| **Macie** | Scans the S3 bucket for sensitive data | Flags the fake PII as sensitive |
| **CloudTrail** | Records all API activity | Evidence/audit trail of everything done |
| **VPC Flow Logs** | Records network traffic | Feeds GuardDuty; shows the attack traffic |

---

## Network layout (simple, lab-grade)

- **Attacker VPC:** `10.0.0.0/16`, 1 public subnet, IGW, Kali EC2 with public IP.
- **Defender VPC:** `10.1.0.0/16`, 1-2 public subnets (ALB needs 2 AZs), IGW, target EC2 + ALB.
- **No VPC peering** — traffic goes over the internet (realistic external attack).
- **WAF** attached to the ALB.
- **VPC Flow Logs** enabled on the Defender VPC (feeds GuardDuty + evidence).

---

## Region

Use a single region for everything (e.g. **ap-southeast-5** or **ap-southeast-1**). Keep it consistent — GuardDuty, Inspector, Detective, WAF (on ALB), and Macie are all regional and must be enabled in the **same region** you deploy the resources.

---

## Why this design works for learning

- **Realistic:** external attacker → WAF → ALB → app is a real internet-facing pattern.
- **Full detection coverage:** each attack maps to at least one AWS defense (see `02-attack-plan.md`).
- **Cheap:** 2 small EC2s + short-lived security services = under $60 for a day.
- **Safe:** self-owned, isolated, deliberately vulnerable apps only.

---

## Open design questions (confirm before build)

1. **Which vulnerable app** — DVWA (classic, PHP, great for SQLi/XSS) or OWASP Juice Shop (modern, more OWASP Top 10 coverage)? *(Recommend: DVWA for simplicity, Juice Shop for breadth.)*
2. **Region** — ap-southeast-5 (Malaysia) or ap-southeast-1 (Singapore)? *(Singapore has more service maturity; Malaysia is closer.)*
3. **Access method** — SSM Session Manager (no open ports, safer) or SSH key?
4. **Dedicated sandbox account** available, or an isolated VPC in an existing one? *(Strongly recommend a separate/sandbox account.)*
