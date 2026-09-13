# Attacking Environment - Console Deployment Notes

**Fully console-based** (no IaC). Single account, separated by **VPC only** (no separate sandbox account).
Region: **ap-southeast-5 (Malaysia)** | Access: **SSM Session Manager** (no SSH).

> Build this Attacker VPC first, then build the Defensive env (separate note). They live in the **same account** but **different VPCs**, and talk over the internet.

---

## What you'll build here

- **Attacker VPC** `10.0.0.0/16` with 1 public subnet
- **Internet Gateway** + route
- **Kali Linux EC2** (t3.small) with **SSM access** (no SSH ports)
- IAM role so SSM works

---

## Step 0 - Prerequisites

1. Sign in to the AWS Console, region **ap-southeast-5**.
2. Set a **Budget alert** ($60): Billing → Budgets → Create budget → Cost budget → $60 → email alert at 80%.
3. **Subscribe to Kali Linux AMI** (one-time, free):
   - Console → **AWS Marketplace Subscriptions** → Manage subscriptions → search **Kali Linux** → **Subscribe**.
   - Or during instance launch (Step 4) choose the Kali AMI from Marketplace directly.

---

## Step 1 - Create the Attacker VPC

1. Console → **VPC** → **Your VPCs** → **Create VPC**.
2. Choose **VPC only** (not "VPC and more", we'll keep it simple/manual).
3. Settings:
   - **Name tag:** `lab-attacker-vpc`
   - **IPv4 CIDR:** `10.0.0.0/16`
   - Leave IPv6 none, Tenancy default.
4. **Create VPC**.

---

## Step 2 - Create a public subnet

1. VPC → **Subnets** → **Create subnet**.
2. **VPC:** select `lab-attacker-vpc`.
3. **Subnet name:** `lab-attacker-subnet`
4. **Availability Zone:** pick any (e.g. ap-southeast-5a)
5. **IPv4 CIDR:** `10.0.1.0/24`
6. **Create subnet**.
7. Select the subnet → **Actions → Edit subnet settings** → tick **Enable auto-assign public IPv4 address** → Save.

---

## Step 3 - Internet Gateway + route

1. VPC → **Internet gateways** → **Create internet gateway** → name `lab-attacker-igw` → Create.
2. Select it → **Actions → Attach to VPC** → choose `lab-attacker-vpc`.
3. VPC → **Route tables** → find the route table for `lab-attacker-vpc` (or create one and associate the subnet).
4. Select it → **Routes** tab → **Edit routes** → **Add route**:
   - Destination `0.0.0.0/0` → Target: **Internet Gateway** → `lab-attacker-igw` → Save.
5. **Subnet associations** tab → **Edit subnet associations** → tick `lab-attacker-subnet` → Save.

---

## Step 4 - IAM role for SSM (so you can connect without SSH)

1. Console → **IAM** → **Roles** → **Create role**.
2. **Trusted entity:** AWS service → **EC2** → Next.
3. **Permissions:** search and select **`AmazonSSMManagedInstanceCore`** → Next.
4. **Role name:** `lab-ssm-role` → **Create role**.

(You'll reuse this same role for the target EC2 in the defensive env too.)

---

## Step 5 - Security group for Kali

1. VPC (or EC2) → **Security Groups** → **Create security group**.
2. **Name:** `lab-kali-sg`  | **VPC:** `lab-attacker-vpc`
3. **Inbound rules:** leave **empty** (SSM needs no inbound).
4. **Outbound rules:** keep default **All traffic → 0.0.0.0/0** (Kali needs outbound to attack + reach SSM).
5. **Create security group**.

---

## Step 6 - Launch the Kali EC2

1. Console → **EC2** → **Instances** → **Launch instances**.
2. **Name:** `lab-kali-attacker`
3. **Application and OS Image (AMI):**
   - Click **Browse more AMIs** → **AWS Marketplace AMIs** tab → search **Kali Linux** → Select the official Kali image → Subscribe/Continue if prompted.
4. **Instance type:** `t3.small`
5. **Key pair:** choose **Proceed without a key pair** (we use SSM, not SSH).
6. **Network settings** → **Edit**:
   - **VPC:** `lab-attacker-vpc`
   - **Subnet:** `lab-attacker-subnet`
   - **Auto-assign public IP:** **Enable**
   - **Security group:** select existing → `lab-kali-sg`
7. **Advanced details** → **IAM instance profile:** select `lab-ssm-role`.
8. **Launch instance**.

---

## Step 7 - Connect to Kali via SSM

1. Wait ~2-3 min for the instance + SSM agent to register.
2. Console → **Systems Manager** → **Session Manager** → **Start session**.
3. Select `lab-kali-attacker` → **Start session**.
4. You now have a shell on Kali - no SSH, no open ports.

**If Kali doesn't appear in Session Manager:**
- Confirm the IAM role `lab-ssm-role` is attached (EC2 → instance → Security).
- Confirm the instance has a public IP + the IGW route (needs outbound to reach SSM).
- Wait a few more minutes for the agent.
- Kali sometimes needs the SSM agent installed/started - if missing, that's when you fall back to CLI/SSH.

---

## Step 8 - Verify the attack tools

In the SSM session:
```bash
which nmap sqlmap nikto hydra
# Kali ships with these; if any missing:
sudo apt update && sudo apt install -y nmap sqlmap nikto hydra
```

---

## Done - Attacker env ready

You now have Kali reachable via SSM, able to attack over the internet.

**Next:** build the **Defensive environment** (`DEFENSIVE-ENV-console.md`), then from this Kali box attack the DVWA URL.

> Note the Kali instance ID and keep this session handy. When you run the attacks (see `../02-attack-plan.md`), you target the **DVWA ALB URL** produced in the defensive env.

---

## Teardown (attacker side)

At end of lab:
1. EC2 → terminate `lab-kali-attacker`.
2. VPC → delete `lab-attacker-vpc` (delete subnet, IGW detach+delete, route table first if needed).
3. (Keep `lab-ssm-role` if reusing; otherwise delete it.)
