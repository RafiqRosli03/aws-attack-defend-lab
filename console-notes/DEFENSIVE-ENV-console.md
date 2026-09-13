# Defensive Environment - Console Deployment Notes

**Fully console-based** (no IaC). Same account as the attacker, **separate VPC**.
Region: **ap-southeast-5 (Malaysia)**.

> Build this AFTER the Attacker VPC. This is the target the Kali box attacks, plus all the AWS defenses that detect the attacks.

---

## What you'll build here

- **Defender VPC** `10.1.0.0/16` with **2 public subnets** (ALB needs 2 AZs)
- Internet Gateway + route
- **DVWA target EC2** (Docker) - SSM access
- **Application Load Balancer** in front of DVWA
- **AWS WAF** web ACL on the ALB (SQLi / Common / rate-limit rules)
- **S3 bucket** with fake PII (for Macie)
- Enable: **GuardDuty, Inspector, Macie, Detective, Security Hub** + **VPC Flow Logs**

---

## Step 1 - Create the Defender VPC + 2 subnets

1. **VPC → Create VPC → VPC only**
   - Name: `lab-defender-vpc` | CIDR: `10.1.0.0/16` → Create.
2. **Subnets → Create subnet** (do this twice, different AZs):
   - Subnet A: name `lab-defender-subnet-a`, AZ `ap-southeast-5a`, CIDR `10.1.1.0/24`
   - Subnet B: name `lab-defender-subnet-b`, AZ `ap-southeast-5b`, CIDR `10.1.2.0/24`
3. For **each** subnet: Actions → Edit subnet settings → **Enable auto-assign public IPv4** → Save.

---

## Step 2 - Internet Gateway + route

1. **Internet gateways → Create** → `lab-defender-igw` → attach to `lab-defender-vpc`.
2. **Route tables** → the VPC's route table → **Edit routes** → add `0.0.0.0/0` → `lab-defender-igw`.
3. **Subnet associations** → associate **both** subnets A and B.

---

## Step 3 - Security groups

**ALB security group:**
1. Security Groups → Create → name `lab-alb-sg`, VPC `lab-defender-vpc`.
2. Inbound: **HTTP 80** from `0.0.0.0/0` (so the attacker reaches it). Outbound default.

**Target security group:**
1. Create → name `lab-target-sg`, VPC `lab-defender-vpc`.
2. Inbound: **HTTP 80**, Source = **`lab-alb-sg`** (only the ALB can reach DVWA directly). Outbound default.

---

## Step 4 - Launch the DVWA target EC2

1. **EC2 → Launch instances**
   - Name: `lab-dvwa-target`
   - AMI: **Amazon Linux 2023**
   - Type: `t3.small`
   - Key pair: **Proceed without a key pair** (SSM).
2. **Network settings → Edit:**
   - VPC: `lab-defender-vpc` | Subnet: `lab-defender-subnet-a` | Auto-assign public IP: **Enable**
   - Security group: existing → `lab-target-sg`
3. **Advanced details → IAM instance profile:** `lab-ssm-role` (the same role from the attacker note).
4. **Advanced details → User data:** paste this to auto-install DVWA:
   ```bash
   #!/bin/bash
   dnf update -y
   dnf install -y docker
   systemctl enable --now docker
   docker run -d --restart unless-stopped -p 80:80 vulnerables/web-dvwa
   ```
5. **Launch instance.** Wait ~3-5 min for DVWA to start.

---

## Step 5 - Create the target group + ALB

**Target group:**
1. **EC2 → Target groups → Create target group**
   - Type: **Instances** | Name: `lab-dvwa-tg` | Protocol HTTP 80 | VPC `lab-defender-vpc`
   - Health check path: `/` | Advanced: success codes `200,302`
   - **Register targets:** select `lab-dvwa-target` → Include as pending → Create.

**ALB:**
1. **EC2 → Load balancers → Create load balancer → Application Load Balancer**
   - Name: `lab-dvwa-alb` | Scheme: **Internet-facing** | IP type: IPv4
   - **Network mapping:** VPC `lab-defender-vpc` → tick **both** subnets A and B.
   - **Security group:** `lab-alb-sg` (remove default).
   - **Listener:** HTTP 80 → forward to **`lab-dvwa-tg`**.
   - **Create load balancer.**
2. Copy the ALB **DNS name** - this is your **DVWA URL** (`http://lab-dvwa-alb-xxxx.ap-southeast-5.elb.amazonaws.com`). This is what Kali attacks.

**Confirm DVWA works:** open the ALB URL in a browser → login `admin/password` → **Create/Reset Database** → **DVWA Security = Low**.

---

## Step 6 - Attach AWS WAF to the ALB

1. Console → **WAF & Shield** → **Web ACLs** → **Create web ACL**.
2. **Region:** make sure it's **Asia Pacific (Malaysia) ap-southeast-5** (regional, NOT CloudFront).
3. **Name:** `lab-dvwa-webacl`
4. **Associated AWS resources → Add** → choose **Application Load Balancer** → `lab-dvwa-alb`.
5. **Add rules → Add managed rule groups → AWS managed rule groups:**
   - **SQL database** (SQLi) → Add
   - **Core rule set** (Common, catches XSS etc.) → Add
6. **Add your own rule → Rate-based rule:**
   - Name `RateLimit` | Rate limit `100` | Based on source IP | Action **Block** → Add.
7. Default action: **Allow**. → Create web ACL.

---

## Step 7 - S3 bucket with fake PII (for Macie)

1. **S3 → Create bucket** → name `lab-macie-fakepii-<something-unique>` | region ap-southeast-5 | Block all public access **ON** → Create.
2. Create a local file `fake-pii.csv` (all FAKE data):
   ```
   name,email,credit_card,ssn
   John Doe,john.doe@example.com,4111111111111111,123-45-6789
   Jane Smith,jane.smith@example.com,5500005555555559,987-65-4321
   ```
3. Upload it to the bucket (S3 → bucket → Upload).

---

## Step 8 - Enable the defensive security services (console)

All in **ap-southeast-5**. Most have a free trial.

1. **GuardDuty:** GuardDuty console → **Enable GuardDuty**.
2. **Security Hub:** Security Hub console → **Go to Security Hub / Enable** → enable default standards.
3. **Inspector:** Inspector console → **Activate Inspector** → enable **EC2 scanning**.
4. **Macie:** Macie console → **Get started / Enable Macie**. Then **Create job** → select the fake-PII bucket → one-time job → Create.
5. **Detective:** Detective console → **Enable Amazon Detective**.

> Let GuardDuty + Inspector baseline ~30-60 min before attacking.

---

## Step 9 - Enable VPC Flow Logs (feeds GuardDuty + evidence)

1. **VPC → Your VPCs →** select `lab-defender-vpc` → **Flow logs** tab → **Create flow log**.
2. Filter: **All** | Destination: **CloudWatch Logs** (create a log group `/lab/defender-vpc/flowlogs`) or **S3**.
3. If CloudWatch, create/select an IAM role that allows flow logs to write (console can create one for you). → Create.

---

## Step 10 - Ready to attack

- DVWA URL = the **ALB DNS name** from Step 5.
- Go to your **Kali SSM session** (attacker note) and run the 5 attacks from `../02-attack-plan.md` against that URL.
- Then collect evidence:

| Service | Where to look |
|---------|---------------|
| WAF | Web ACL `lab-dvwa-webacl` → **Sampled requests** (filter Block) |
| GuardDuty | **Findings** (port scan / recon) |
| Inspector | **Findings** (CVEs on `lab-dvwa-target`) |
| Macie | **Findings** (sensitive data in the bucket) |
| Security Hub | **Summary** + **Findings** (aggregated + score) |
| Detective | search the attacker IP → investigation graph |

---

## Teardown (defensive side) - do same day

Order matters (dependencies):
1. **WAF** → Web ACLs → `lab-dvwa-webacl` → **disassociate** the ALB → **delete** the web ACL.
2. **EC2 → Load balancers →** delete `lab-dvwa-alb`.
3. **EC2 → Target groups →** delete `lab-dvwa-tg`.
4. **EC2 →** terminate `lab-dvwa-target`.
5. **S3 →** empty + delete `lab-macie-fakepii-*`.
6. **Disable services:** GuardDuty, Inspector, Macie, Detective, Security Hub (each console → settings → disable).
7. **VPC →** delete flow logs, then delete `lab-defender-vpc` (subnets, IGW, route table).
8. **Verify** in Billing next day that nothing lab-related is still charging.

> The ALB + WAF + any Elastic IPs bill hourly, and the security services bill after free trial - so teardown is the one step you must not skip.
