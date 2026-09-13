# 03 - Cost Estimate & Same-Day Teardown

Target: **under $60 total**, used for **1 day**, then torn down. Good news: most of the security services have a **30-day free trial**, so for a 1-day lab they're often **$0**.

---

## The big cost-saver: free trials

Per AWS documentation, these have a **30-day free trial per new account per region**:

| Service | Free trial | Source |
|---------|-----------|--------|
| **GuardDuty** | 30-day free trial (per account, per region) | [GuardDuty pricing](https://aws.amazon.com/guardduty/pricing/) |
| **Macie** | 30-day free trial (sensitive data discovery, up to 10k buckets) | [Macie free trial](https://docs.aws.amazon.com/macie/latest/user/account-mgmt-free-trial.html) |
| **Detective** | 30-day free trial | [Detective pricing](https://aws.amazon.com/detective/pricing/) |
| **Inspector** | 15-day free trial (typical) | [Inspector pricing](https://aws.amazon.com/inspector/pricing/) |
| **Security Hub** | 30-day free trial | AWS free security tier |

> If this account/region hasn't used these before, a **1-day lab falls entirely inside the free trial → $0** for GuardDuty, Macie, Detective, Inspector, Security Hub. Confirm "free trial" status in each service's console before enabling.

Content was rephrased for compliance with licensing restrictions.

---

## What you actually pay for (the non-trial items)

| Item | Est. cost for 1 day | Notes |
|------|--------------------|-------|
| **Kali EC2 (t3.small)** | ~$0.50-0.60 | ~$0.025/hr x ~24h; less if you stop it |
| **Target EC2 (t3.small)** | ~$0.50-0.60 | same |
| **Application Load Balancer** | ~$0.60-0.80 | ~$0.0225/hr + tiny LCU; **biggest fixed cost** |
| **AWS WAF** | ~$1-2 | $5/mo per web ACL prorated + $1/rule + tiny per-request; a day is a fraction |
| **EBS volumes (2x ~30GB gp3)** | ~$0.20 | prorated daily |
| **Public IPv4 (2 addresses)** | ~$0.25 | ~$0.005/hr each now that AWS charges for IPv4 |
| **VPC Flow Logs + CloudTrail + S3** | <$0.20 | tiny for a day |
| **Data transfer** | <$0.50 | small attack traffic |
| **Security services (GuardDuty/Macie/Detective/Inspector/Security Hub)** | **$0** if in free trial | otherwise a few $ prorated for 1 day |

### Realistic total
- **With free trials active:** ~**$4-6** for the whole day (just EC2 + ALB + WAF + IPs).
- **Without free trials (worst case):** still typically **~$15-25** for 1 day, well under $60.

**You are very safely under $60.** The real risk isn't the daily rate — it's **forgetting to tear down** and letting it run for weeks.

---

## The #1 rule: TEAR DOWN THE SAME DAY

The services are cheap per-day but add up if left running (especially after free trials end, and the ALB/WAF/EIP bill hourly forever). **Teardown is mandatory.**

### Teardown checklist (do ALL of these at end of day)

**1. Terminate EC2 instances**
```bash
aws ec2 describe-instances --region <region> --query "Reservations[].Instances[].InstanceId" --output text
aws ec2 terminate-instances --region <region> --instance-ids <kali-id> <target-id>
```

**2. Delete the ALB + target group + WAF**
```bash
aws elbv2 delete-load-balancer --region <region> --load-balancer-arn <alb-arn>
aws elbv2 delete-target-group --region <region> --target-group-arn <tg-arn>
# WAF: disassociate then delete the web ACL
aws wafv2 delete-web-acl --scope REGIONAL --region <region> --name <acl> --id <id> --lock-token <token>
```

**3. Release Elastic IPs** (so you stop paying for IPv4)
```bash
aws ec2 describe-addresses --region <region> --query "Addresses[].AllocationId" --output text
aws ec2 release-address --region <region> --allocation-id <alloc-id>
```

**4. Disable the security services** (stops any post-trial charges)
- **GuardDuty:** Settings → Suspend/Disable
- **Macie:** Settings → Disable Macie
- **Detective:** disable the behavior graph
- **Inspector:** deactivate scanning
- **Security Hub:** disable (optional)

**5. Delete S3 buckets** (the fake-PII bucket + any log buckets you made for the lab)
```bash
aws s3 rb s3://<lab-bucket> --force
```

**6. Delete the VPCs** (attacker + defender) once instances/ALB are gone
- Delete via console (VPC → Delete VPC removes subnets, IGW, route tables, flow logs).

**7. Turn off VPC Flow Logs / CloudTrail trail** if you created dedicated ones for the lab.

**8. Verify nothing is left billing:**
```bash
# quick sweep
aws ec2 describe-instances --region <region> --query "Reservations[].Instances[].State.Name"
aws elbv2 describe-load-balancers --region <region> --query "LoadBalancers[].LoadBalancerName"
aws ec2 describe-addresses --region <region> --query "Addresses[].PublicIp"
```

---

## Cost guardrails (set these BEFORE you start)

1. **AWS Budget alert:** create a $60 budget with alerts at 50% / 80% / 100% so you get emailed if it creeps up.
   ```bash
   # or set in Billing > Budgets console
   ```
2. **Stop (don't terminate) EC2s** during long waits to save compute.
3. **Set a calendar reminder** for teardown at end of day.
4. **Use a dedicated sandbox account** so cleanup is easy and nothing mixes with real workloads.

---

## Summary

- **Expected cost for a 1-day lab: ~$5-25**, comfortably under $60.
- **Free trials** likely make GuardDuty/Macie/Detective/Inspector/Security Hub **$0**.
- **Teardown the same day** is the one thing that must not be skipped.
- **Set a $60 budget alert** before starting as a safety net.

> Note: prices vary by region and change over time. Confirm current rates in the [AWS Pricing Calculator](https://calculator.aws) and each service's pricing page before you build. The free-trial status must be checked per service in your account/region.
