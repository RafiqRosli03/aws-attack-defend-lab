<#
.SYNOPSIS
  Tears down the Attack & Defend lab and stops all billing.
  Deletes the CloudFormation stack (VPCs, EC2s, ALB, WAF, S3, flow logs)
  and disables the security services (GuardDuty/Inspector/Macie/Detective/Security Hub).

.USAGE
  # Preview what will be removed (no changes):
  .\teardown.ps1

  # Actually tear everything down:
  .\teardown.ps1 -Apply
#>

param(
    [string]$Region = "ap-southeast-5",
    [string]$StackName = "attack-defend-lab",
    [switch]$Apply
)

$ErrorActionPreference = "Continue"
Write-Host "Region: $Region | Stack: $StackName" -ForegroundColor Cyan
if (-not $Apply) { Write-Host "PREVIEW MODE - nothing will be deleted. Re-run with -Apply.`n" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# 1. Empty the Macie S3 bucket (buckets must be empty before stack delete)
# ---------------------------------------------------------------------------
$bucket = aws cloudformation describe-stacks --region $Region --stack-name $StackName `
    --query "Stacks[0].Outputs[?OutputKey=='MacieBucketName'].OutputValue" --output text 2>$null

if ($bucket -and $bucket -ne "None") {
    Write-Host "S3 bucket to empty: $bucket" -ForegroundColor Yellow
    if ($Apply) {
        aws s3 rm "s3://$bucket" --recursive
        Write-Host "  emptied $bucket"
    }
}

# ---------------------------------------------------------------------------
# 2. Delete the CloudFormation stack (removes VPCs, EC2, ALB, WAF, flow logs, bucket)
# ---------------------------------------------------------------------------
if ($Apply) {
    Write-Host "Deleting CloudFormation stack '$StackName'..." -ForegroundColor Yellow
    aws cloudformation delete-stack --region $Region --stack-name $StackName
    Write-Host "  delete initiated. Waiting for completion..."
    aws cloudformation wait stack-delete-complete --region $Region --stack-name $StackName
    Write-Host "  stack deleted." -ForegroundColor Green
} else {
    Write-Host "[preview] would delete stack $StackName (VPCs, EC2s, ALB, WAF, S3, flow logs)"
}

# ---------------------------------------------------------------------------
# 3. Disable the security services (stop any post-free-trial charges)
# ---------------------------------------------------------------------------
Write-Host "Disabling security services..." -ForegroundColor Yellow

if ($Apply) {
    # GuardDuty - delete detector
    $det = aws guardduty list-detectors --region $Region --query "DetectorIds[0]" --output text 2>$null
    if ($det -and $det -ne "None") { aws guardduty delete-detector --detector-id $det --region $Region; Write-Host "  GuardDuty disabled" }

    # Inspector - disable EC2 scanning
    aws inspector2 disable --resource-types EC2 --region $Region 2>$null; Write-Host "  Inspector disabled"

    # Macie - disable
    aws macie2 disable-macie --region $Region 2>$null; Write-Host "  Macie disabled"

    # Detective - delete graph
    $graph = aws detective list-graphs --region $Region --query "GraphList[0].Arn" --output text 2>$null
    if ($graph -and $graph -ne "None") { aws detective delete-graph --graph-arn $graph --region $Region; Write-Host "  Detective graph deleted" }

    # Security Hub - disable
    aws securityhub disable-security-hub --region $Region 2>$null; Write-Host "  Security Hub disabled"
} else {
    Write-Host "[preview] would disable GuardDuty, Inspector, Macie, Detective, Security Hub in $Region"
}

# ---------------------------------------------------------------------------
# 4. Verify nothing is left billing
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "===== VERIFICATION =====" -ForegroundColor Cyan
Write-Host "-- EC2 instances (should be terminated/empty) --"
aws ec2 describe-instances --region $Region `
  --filters "Name=tag:Name,Values=lab-*" `
  --query "Reservations[].Instances[?State.Name!='terminated'].{ID:InstanceId,State:State.Name}" --output table

Write-Host "-- Load balancers (should be empty) --"
aws elbv2 describe-load-balancers --region $Region `
  --query "LoadBalancers[?contains(LoadBalancerName,'lab')].LoadBalancerName" --output text

Write-Host "-- Elastic IPs (should be none for the lab) --"
aws ec2 describe-addresses --region $Region --query "Addresses[].PublicIp" --output text

Write-Host ""
if ($Apply) {
    Write-Host "TEARDOWN COMPLETE. Double-check the verification output above shows nothing left." -ForegroundColor Green
} else {
    Write-Host "PREVIEW done. Re-run with -Apply to actually tear down." -ForegroundColor Cyan
}
Write-Host "Reminder: also confirm your Billing dashboard shows no ongoing lab charges tomorrow." -ForegroundColor Yellow
