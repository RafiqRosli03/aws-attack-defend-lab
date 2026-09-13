# Resume the Lab (after Option B shutdown)

Last session: stopped both EC2 instances + deleted ALB & WAF (Option B). EC2s preserve all tools/DVWA.
Run in **CloudShell**, region ap-southeast-5.

## Known IDs (from deployment)
```
REGION=ap-southeast-5
ACCOUNT=497862079645
DEF_VPC=vpc-0db220f0ae1d00e0c
ATT_VPC=vpc-045d916256976f0f3
DEF_SUBNET_A / DEF_SUBNET_B  (look up by name lab-defender-subnet-a/-b)
ALB_SG=sg-098fe6e7b500c78a7
TARGET_SG=sg-0519f664f5de763ea
KALI_SG=sg-05822d7c6dd915799
TARGET_ID=i-0cb7fc3bc3d1be6e6
KALI (tag lab-kali-attacker)
MACIE_BUCKET=lab-macie-fakepii-497862079645
```

## Step 1 - Start the instances
```bash
export REGION=ap-southeast-5
IDS=$(aws ec2 describe-instances --region $REGION \
  --filters "Name=tag:Project,Values=attack-defend-lab" "Name=instance-state-name,Values=stopped" \
  --query "Reservations[].Instances[].InstanceId" --output text)
aws ec2 start-instances --region $REGION --instance-ids $IDS
echo "Starting: $IDS"
```

## Step 2 - Recover IDs
```bash
export DEF_VPC=vpc-0db220f0ae1d00e0c
export DEF_SUBNET_A=$(aws ec2 describe-subnets --region $REGION --filters "Name=tag:Name,Values=lab-defender-subnet-a" --query "Subnets[0].SubnetId" --output text)
export DEF_SUBNET_B=$(aws ec2 describe-subnets --region $REGION --filters "Name=tag:Name,Values=lab-defender-subnet-b" --query "Subnets[0].SubnetId" --output text)
export ALB_SG=$(aws ec2 describe-security-groups --region $REGION --filters "Name=group-name,Values=lab-alb-sg" --query "SecurityGroups[0].GroupId" --output text)
export KALI_SG=$(aws ec2 describe-security-groups --region $REGION --filters "Name=group-name,Values=lab-kali-sg" --query "SecurityGroups[0].GroupId" --output text)
export TARGET_ID=$(aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=lab-dvwa-target" "Name=instance-state-name,Values=running,pending" --query "Reservations[].Instances[].InstanceId" --output text)
export KALI_ID=$(aws ec2 describe-instances --region $REGION --filters "Name=tag:Name,Values=lab-kali-attacker" "Name=instance-state-name,Values=running,pending" --query "Reservations[].Instances[].InstanceId" --output text)
echo "SubnetA=$DEF_SUBNET_A SubnetB=$DEF_SUBNET_B ALB_SG=$ALB_SG KALI_SG=$KALI_SG TARGET=$TARGET_ID KALI=$KALI_ID"
```

## Step 3 - Rebuild target group + ALB + listener
```bash
export TG_ARN=$(aws elbv2 create-target-group --region $REGION \
  --name lab-dvwa-tg --protocol HTTP --port 80 --vpc-id $DEF_VPC \
  --target-type instance --health-check-path / --matcher '{"HttpCode":"200,302"}' \
  --query "TargetGroups[0].TargetGroupArn" --output text)
aws elbv2 register-targets --region $REGION --target-group-arn $TG_ARN --targets Id=$TARGET_ID

export ALB_ARN=$(aws elbv2 create-load-balancer --region $REGION \
  --name lab-dvwa-alb --type application --scheme internet-facing \
  --subnets $DEF_SUBNET_A $DEF_SUBNET_B --security-groups $ALB_SG \
  --query "LoadBalancers[0].LoadBalancerArn" --output text)
aws elbv2 create-listener --region $REGION --load-balancer-arn $ALB_ARN \
  --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$TG_ARN

export DVWA_URL=$(aws elbv2 describe-load-balancers --region $REGION --load-balancer-arns $ALB_ARN --query "LoadBalancers[0].DNSName" --output text)
echo "NEW DVWA URL: http://$DVWA_URL/"
```

## Step 4 - Rebuild + attach WAF (wait for ALB active first)
```bash
aws elbv2 wait load-balancer-available --region $REGION --load-balancer-arns $ALB_ARN

cat > /tmp/waf-rules.json << 'EOF'
[
  {"Name":"SQLi","Priority":1,"OverrideAction":{"None":{}},"Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesSQLiRuleSet"}},"VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"sqli"}},
  {"Name":"Common","Priority":2,"OverrideAction":{"None":{}},"Statement":{"ManagedRuleGroupStatement":{"VendorName":"AWS","Name":"AWSManagedRulesCommonRuleSet"}},"VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"common"}},
  {"Name":"RateLimit","Priority":3,"Action":{"Block":{}},"Statement":{"RateBasedStatement":{"Limit":100,"AggregateKeyType":"IP"}},"VisibilityConfig":{"SampledRequestsEnabled":true,"CloudWatchMetricsEnabled":true,"MetricName":"rate"}}
]
EOF
export WAF_ARN=$(aws wafv2 create-web-acl --region $REGION --name lab-dvwa-webacl --scope REGIONAL \
  --default-action Allow={} \
  --visibility-config SampledRequestsEnabled=true,CloudWatchMetricsEnabled=true,MetricName=labDvwaWebAcl \
  --rules file:///tmp/waf-rules.json --query "Summary.ARN" --output text)
aws wafv2 associate-web-acl --region $REGION --web-acl-arn $WAF_ARN --resource-arn $ALB_ARN
aws wafv2 get-web-acl-for-resource --region $REGION --resource-arn $ALB_ARN --query "WebACL.Name" --output text
```

## Step 5 - Reconnect to Kali (new IP)
```bash
# new public IP (changes on restart)
export KALI_IP=$(aws ec2 describe-instances --region $REGION --instance-ids $KALI_ID --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo "New Kali IP: $KALI_IP"

# re-open SSH from your CURRENT laptop IP (check https://checkip.amazonaws.com on laptop)
# aws ec2 authorize-security-group-ingress --region $REGION --group-id $KALI_SG --protocol tcp --port 22 --cidr YOURIP/32
```
Then PuTTY: `kali@<KALI_IP>` with lab-kali-key.ppk.

## Step 6 - Verify + attack
```bash
curl -I http://$DVWA_URL/     # expect 302 -> login.php
```
Then in Kali:
```bash
TARGET="<paste new DVWA_URL>"
nmap -sV -Pn $TARGET          # Attack 1
```
Continue the 5 attacks from 02-attack-plan.md.

## End of session - shut down again (Option B)
- Stop instances + delete ALB + WAF (same as last night). See teardown in CLI-DEPLOY-STEP-BY-STEP.md.
