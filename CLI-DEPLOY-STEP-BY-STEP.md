# CLI Deployment - Step by Step (Attack & Defend Lab)

Full CLI deployment for the lab in **ap-southeast-5**, single account, VPC-separated.
Run these in **CloudShell** (in your lab account `497862079645`). Copy-paste one block at a time.

> Every resource is tagged `Project=attack-defend-lab` so cleanup is easy.
> Keep this session open - we save IDs into shell variables as we go. If your session resets, re-run the discovery block in **Phase 8** to recover IDs.

---

## PHASE 0 - Prep (region, budget, Kali subscription)

```bash
# region + account
export REGION=ap-southeast-5
export ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
echo "Account $ACCOUNT | Region $REGION"
```

### Budget ($60, email alerts)
```bash
export EMAIL="your-email@example.com"   # <-- CHANGE THIS

cat > /tmp/budget.json << EOF
{ "BudgetName":"lab-60-usd-budget","BudgetLimit":{"Amount":"60","Unit":"USD"},"TimeUnit":"MONTHLY","BudgetType":"COST" }
EOF
cat > /tmp/notif.json << EOF
[{"Notification":{"NotificationType":"ACTUAL","ComparisonOperator":"GREATER_THAN","Threshold":80,"ThresholdType":"PERCENTAGE"},
  "Subscribers":[{"SubscriptionType":"EMAIL","Address":"$EMAIL"}]}]
EOF
aws budgets create-budget --account-id "$ACCOUNT" --budget file:///tmp/budget.json --notifications-with-subscribers file:///tmp/notif.json
echo "Budget set."
```

### Subscribe to Kali AMI (ONE manual step - can't be done by CLI)
- Go to AWS Marketplace in console, search **Kali Linux**, click **Subscribe** (free).
- Then get the AMI ID for ap-southeast-5:
```bash
# Kali is published by kali-linux / owner 679593333241 (verify the name in Marketplace)
aws ec2 describe-images --region $REGION --owners aws-marketplace \
  --filters "Name=name,Values=*kali-linux*" \
  --query "reverse(sort_by(Images,&CreationDate))[:5].{Name:Name,ID:ImageId,Date:CreationDate}" --output table
```
Copy the newest Kali AMI ID:
```bash
export KALI_AMI=ami-xxxxxxxxxxxxxxxxx   # <-- paste from above
```

### Get the latest Amazon Linux 2023 AMI (for the DVWA target) - automatic
```bash
export AL2023_AMI=$(aws ssm get-parameter --region $REGION \
  --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query "Parameter.Value" --output text)
echo "AL2023 AMI: $AL2023_AMI"
```

---

## PHASE 1 - Shared SSM IAM role (used by both EC2s)

```bash
# trust policy
cat > /tmp/trust.json << 'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF

aws iam create-role --role-name lab-ssm-role --assume-role-policy-document file:///tmp/trust.json
aws iam attach-role-policy --role-name lab-ssm-role \
  --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
aws iam create-instance-profile --instance-profile-name lab-ssm-profile
aws iam add-role-to-instance-profile --instance-profile-name lab-ssm-profile --role-name lab-ssm-role
echo "Waiting for instance profile to propagate..."; sleep 15
```

---

## PHASE 2 - Attacker VPC (Kali)

```bash
# VPC
export ATT_VPC=$(aws ec2 create-vpc --region $REGION --cidr-block 10.0.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-attacker-vpc},{Key=Project,Value=attack-defend-lab}]' \
  --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --region $REGION --vpc-id $ATT_VPC --enable-dns-hostnames
echo "Attacker VPC: $ATT_VPC"

# Subnet (public)
export ATT_SUBNET=$(aws ec2 create-subnet --region $REGION --vpc-id $ATT_VPC \
  --cidr-block 10.0.1.0/24 --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-attacker-subnet}]' \
  --query "Subnet.SubnetId" --output text)
aws ec2 modify-subnet-attribute --region $REGION --subnet-id $ATT_SUBNET --map-public-ip-on-launch
echo "Attacker Subnet: $ATT_SUBNET"

# IGW + attach
export ATT_IGW=$(aws ec2 create-internet-gateway --region $REGION \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=lab-attacker-igw}]' \
  --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --region $REGION --internet-gateway-id $ATT_IGW --vpc-id $ATT_VPC

# Route table + default route + associate
export ATT_RT=$(aws ec2 create-route-table --region $REGION --vpc-id $ATT_VPC \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=lab-attacker-rt}]' \
  --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --region $REGION --route-table-id $ATT_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $ATT_IGW
aws ec2 associate-route-table --region $REGION --route-table-id $ATT_RT --subnet-id $ATT_SUBNET
echo "Attacker networking done."

# Security group (no inbound; SSM uses outbound only)
export KALI_SG=$(aws ec2 create-security-group --region $REGION \
  --group-name lab-kali-sg --description "Kali attacker" --vpc-id $ATT_VPC \
  --query "GroupId" --output text)
echo "Kali SG: $KALI_SG"
```

### Launch Kali
```bash
export KALI_ID=$(aws ec2 run-instances --region $REGION \
  --image-id $KALI_AMI --instance-type t3.small \
  --subnet-id $ATT_SUBNET --security-group-ids $KALI_SG \
  --iam-instance-profile Name=lab-ssm-profile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-kali-attacker},{Key=Project,Value=attack-defend-lab}]' \
  --query "Instances[0].InstanceId" --output text)
echo "Kali instance: $KALI_ID"
```

---

## PHASE 3 - Defender VPC (DVWA target)

```bash
# VPC
export DEF_VPC=$(aws ec2 create-vpc --region $REGION --cidr-block 10.1.0.0/16 \
  --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=lab-defender-vpc},{Key=Project,Value=attack-defend-lab}]' \
  --query "Vpc.VpcId" --output text)
aws ec2 modify-vpc-attribute --region $REGION --vpc-id $DEF_VPC --enable-dns-hostnames
echo "Defender VPC: $DEF_VPC"

# 2 subnets (ALB needs 2 AZs)
export DEF_SUBNET_A=$(aws ec2 create-subnet --region $REGION --vpc-id $DEF_VPC \
  --cidr-block 10.1.1.0/24 --availability-zone ${REGION}a \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-defender-subnet-a}]' \
  --query "Subnet.SubnetId" --output text)
export DEF_SUBNET_B=$(aws ec2 create-subnet --region $REGION --vpc-id $DEF_VPC \
  --cidr-block 10.1.2.0/24 --availability-zone ${REGION}b \
  --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=lab-defender-subnet-b}]' \
  --query "Subnet.SubnetId" --output text)
aws ec2 modify-subnet-attribute --region $REGION --subnet-id $DEF_SUBNET_A --map-public-ip-on-launch
aws ec2 modify-subnet-attribute --region $REGION --subnet-id $DEF_SUBNET_B --map-public-ip-on-launch
echo "Defender subnets: $DEF_SUBNET_A , $DEF_SUBNET_B"

# IGW + route
export DEF_IGW=$(aws ec2 create-internet-gateway --region $REGION \
  --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=lab-defender-igw}]' \
  --query "InternetGateway.InternetGatewayId" --output text)
aws ec2 attach-internet-gateway --region $REGION --internet-gateway-id $DEF_IGW --vpc-id $DEF_VPC
export DEF_RT=$(aws ec2 create-route-table --region $REGION --vpc-id $DEF_VPC \
  --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=lab-defender-rt}]' \
  --query "RouteTable.RouteTableId" --output text)
aws ec2 create-route --region $REGION --route-table-id $DEF_RT --destination-cidr-block 0.0.0.0/0 --gateway-id $DEF_IGW
aws ec2 associate-route-table --region $REGION --route-table-id $DEF_RT --subnet-id $DEF_SUBNET_A
aws ec2 associate-route-table --region $REGION --route-table-id $DEF_RT --subnet-id $DEF_SUBNET_B
echo "Defender networking done."

# Security groups
export ALB_SG=$(aws ec2 create-security-group --region $REGION \
  --group-name lab-alb-sg --description "ALB - HTTP from internet" --vpc-id $DEF_VPC --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --region $REGION --group-id $ALB_SG \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

export TARGET_SG=$(aws ec2 create-security-group --region $REGION \
  --group-name lab-target-sg --description "DVWA - HTTP from ALB only" --vpc-id $DEF_VPC --query "GroupId" --output text)
aws ec2 authorize-security-group-ingress --region $REGION --group-id $TARGET_SG \
  --protocol tcp --port 80 --source-group $ALB_SG
echo "ALB SG: $ALB_SG | Target SG: $TARGET_SG"
```

### Launch DVWA target (auto-installs DVWA via user data)
```bash
cat > /tmp/userdata.sh << 'EOF'
#!/bin/bash
dnf update -y
dnf install -y docker
systemctl enable --now docker
docker run -d --restart unless-stopped -p 80:80 vulnerables/web-dvwa
EOF

export TARGET_ID=$(aws ec2 run-instances --region $REGION \
  --image-id $AL2023_AMI --instance-type t3.small \
  --subnet-id $DEF_SUBNET_A --security-group-ids $TARGET_SG \
  --iam-instance-profile Name=lab-ssm-profile \
  --user-data file:///tmp/userdata.sh \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=lab-dvwa-target},{Key=Project,Value=attack-defend-lab}]' \
  --query "Instances[0].InstanceId" --output text)
echo "DVWA target: $TARGET_ID"
```

---

## PHASE 4 - ALB + Target Group + Listener

```bash
# Target group
export TG_ARN=$(aws elbv2 create-target-group --region $REGION \
  --name lab-dvwa-tg --protocol HTTP --port 80 --vpc-id $DEF_VPC \
  --target-type instance --health-check-path / --matcher HttpCode=200,302 \
  --query "TargetGroups[0].TargetGroupArn" --output text)

# register the target
aws elbv2 register-targets --region $REGION --target-group-arn $TG_ARN --targets Id=$TARGET_ID

# ALB (across both subnets)
export ALB_ARN=$(aws elbv2 create-load-balancer --region $REGION \
  --name lab-dvwa-alb --type application --scheme internet-facing \
  --subnets $DEF_SUBNET_A $DEF_SUBNET_B --security-groups $ALB_SG \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)

# listener HTTP 80 -> target group
aws elbv2 create-listener --region $REGION --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN

# get the DVWA URL
export DVWA_URL=$(aws elbv2 describe-load-balancers --region $REGION \
  --load-balancer-arns $ALB_ARN --query "LoadBalancers[0].DNSName" --output text)
echo "===================================================="
echo " DVWA URL (attack this):  http://$DVWA_URL/"
echo "===================================================="
```

---

## PHASE 5 - AWS WAF (regional, on the ALB)

```bash
cat > /tmp/waf-rules.json << 'EOF'
[
  {"Name":"SQLi","Priority":1,"OverrideAction":{"None":{}},
   "Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesSQLiRuleSet"}},
   "VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"sqli"}},
  {"Name":"Common","Priority":2,"OverrideAction":{"None":{}},
   "Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesCommonRuleSet"}},
   "VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"common"}},
  {"Name":"RateLimit","Priority":3,"Action":{"Block":{}},
   "Statement":{"RateBasedStatement":{"Limit":100,"AggregateKeyType":"IP"}},
   "VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"rate"}}
]
EOF

export WAF_ARN=$(aws wafv2 create-web-acl --region $REGION --name lab-dvwa-webacl --scope REGIONAL \
  --default-action Allow={} \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=labDvwaWebAcl \
  --rules file:///tmp/waf-rules.json \
  --query "Summary.ARN" --output text)
echo "WAF ARN: $WAF_ARN"

# associate WAF with the ALB
aws wafv2 associate-web-acl --region $REGION --web-acl-arn $WAF_ARN --resource-arn $ALB_ARN
echo "WAF attached to ALB."
```

---

## PHASE 6 - S3 fake-PII bucket (for Macie)

```bash
export MACIE_BUCKET="lab-macie-fakepii-$ACCOUNT"
aws s3api create-bucket --region $REGION --bucket $MACIE_BUCKET \
  --create-bucket-configuration LocationConstraint=$REGION
aws s3api put-public-access-block --bucket $MACIE_BUCKET \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

cat > /tmp/fake-pii.csv << 'EOF'
name,email,credit_card,ssn
John Doe,john.doe@example.com,4111111111111111,123-45-6789
Jane Smith,jane.smith@example.com,5500005555555559,987-65-4321
EOF
aws s3 cp /tmp/fake-pii.csv s3://$MACIE_BUCKET/
echo "Macie bucket seeded: $MACIE_BUCKET"
```

---

## PHASE 7 - Enable the defensive security services

```bash
# GuardDuty
aws guardduty create-detector --enable --region $REGION

# Security Hub
aws securityhub enable-security-hub --region $REGION 2>/dev/null || echo "Security Hub may already be on"

# Inspector (EC2 scanning)
aws inspector2 enable --resource-types EC2 --region $REGION

# Macie + one-time sensitive data job on the bucket
aws macie2 enable-macie --region $REGION 2>/dev/null || echo "Macie may already be on"

# Detective
aws detective create-graph --region $REGION 2>/dev/null || echo "Detective graph may already exist"

echo "Security services enabling... allow 30-60 min to baseline before attacking."
```

### VPC Flow Logs (defender VPC) - feeds GuardDuty + evidence
```bash
aws logs create-log-group --region $REGION --log-group-name /lab/defender-vpc/flowlogs 2>/dev/null

cat > /tmp/fl-trust.json << 'EOF'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"vpc-flow-logs.amazonaws.com"},"Action":"sts:AssumeRole"}]}
EOF
aws iam create-role --role-name lab-flowlogs-role --assume-role-policy-document file:///tmp/fl-trust.json 2>/dev/null
aws iam put-role-policy --role-name lab-flowlogs-role --policy-name flowlogs \
  --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["logs:CreateLogStream","logs:PutLogEvents","logs:DescribeLogStreams"],"Resource":"*"}]}'
sleep 10
export FL_ROLE_ARN=$(aws iam get-role --role-name lab-flowlogs-role --query "Role.Arn" --output text)

aws ec2 create-flow-logs --region $REGION --resource-type VPC --resource-ids $DEF_VPC \
  --traffic-type ALL --log-group-name /lab/defender-vpc/flowlogs --deliver-logs-permission-arn $FL_ROLE_ARN
echo "Flow logs enabled on defender VPC."
```

---

## PHASE 8 - Verify everything + save your IDs

```bash
echo "==== SUMMARY ===="
echo "Attacker VPC : $ATT_VPC"
echo "Kali instance: $KALI_ID"
echo "Defender VPC : $DEF_VPC"
echo "DVWA target  : $TARGET_ID"
echo "ALB          : $ALB_ARN"
echo "DVWA URL     : http://$DVWA_URL/"
echo "WAF          : $WAF_ARN"
echo "Macie bucket : $MACIE_BUCKET"

# save to a file so you don't lose them if the session resets
cat > ~/lab-ids.txt << EOF
REGION=$REGION
ATT_VPC=$ATT_VPC
KALI_ID=$KALI_ID
DEF_VPC=$DEF_VPC
TARGET_ID=$TARGET_ID
TG_ARN=$TG_ARN
ALB_ARN=$ALB_ARN
DVWA_URL=$DVWA_URL
WAF_ARN=$WAF_ARN
MACIE_BUCKET=$MACIE_BUCKET
EOF
echo "Saved IDs to ~/lab-ids.txt"
```

### Check instances are running + DVWA is up
```bash
aws ec2 describe-instances --region $REGION \
  --filters "Name=tag:Project,Values=attack-defend-lab" \
  --query "Reservations[].Instances[].{Name:Tags[?Key=='Name']|[0].Value,State:State.Name,IP:PublicIpAddress}" --output table

# after ~5 min, test DVWA responds (should get HTTP 302 to login.php)
curl -I http://$DVWA_URL/
```

---

## PHASE 9 - Connect to Kali (SSM)

```bash
aws ssm start-session --target $KALI_ID --region $REGION
```
Then verify tools:
```bash
which nmap sqlmap nikto hydra
```

---

## You're ready to attack

- **DVWA URL:** `http://$DVWA_URL/` (open in browser, login admin/password, Create/Reset DB, set Security = Low)
- Run the 5 attacks from `02-attack-plan.md` against `$DVWA_URL` from the Kali SSM session.

---

## IMPORTANT - Teardown when done (stops all cost)

```bash
# load saved IDs if session reset:  source ~/lab-ids.txt

# 1. WAF: disassociate + delete
aws wafv2 disassociate-web-acl --region $REGION --resource-arn $ALB_ARN
WAF_ID=$(aws wafv2 list-web-acls --region $REGION --scope REGIONAL --query "WebACLs[?Name=='lab-dvwa-webacl'].Id" --output text)
LOCK=$(aws wafv2 get-web-acl --region $REGION --scope REGIONAL --name lab-dvwa-webacl --id $WAF_ID --query "LockToken" --output text)
aws wafv2 delete-web-acl --region $REGION --scope REGIONAL --name lab-dvwa-webacl --id $WAF_ID --lock-token $LOCK

# 2. ALB + target group
aws elbv2 delete-load-balancer --region $REGION --load-balancer-arn $ALB_ARN
sleep 30
aws elbv2 delete-target-group --region $REGION --target-group-arn $TG_ARN

# 3. Terminate instances
aws ec2 terminate-instances --region $REGION --instance-ids $KALI_ID $TARGET_ID
aws ec2 wait instance-terminated --region $REGION --instance-ids $KALI_ID $TARGET_ID

# 4. Disable security services
DET=$(aws guardduty list-detectors --region $REGION --query "DetectorIds[0]" --output text); [ "$DET" != "None" ] && aws guardduty delete-detector --detector-id $DET --region $REGION
aws inspector2 disable --resource-types EC2 --region $REGION
aws macie2 disable-macie --region $REGION
aws securityhub disable-security-hub --region $REGION
G=$(aws detective list-graphs --region $REGION --query "GraphList[0].Arn" --output text); [ "$G" != "None" ] && aws detective delete-graph --graph-arn $G --region $REGION

# 5. S3 bucket
aws s3 rm s3://$MACIE_BUCKET --recursive; aws s3api delete-bucket --bucket $MACIE_BUCKET --region $REGION

# 6. Flow logs + VPCs (delete IGWs, subnets, route tables, then VPCs) - easiest via console,
#    or extend this with delete-flow-logs / detach-internet-gateway / delete-subnet / delete-vpc.
echo "Core cost items removed. Delete the 2 VPCs + flow logs to finish."
```

> Remember: NAT gateways are the big cost - this lab does NOT create one, so you're safe there. The ALB + any EIP are the hourly items; teardown removes them.
