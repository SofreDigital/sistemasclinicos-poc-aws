# SistemasClinicos PoC Deployment Script (PowerShell)
# This script helps deploy the AWS infrastructure using Terraform

param(
    [switch]$SkipConfirmation
)

Write-Host "🚀 SistemasClinicos PoC - AWS Infrastructure Deployment" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

# Check if terraform is installed
if (!(Get-Command terraform -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Terraform is not installed. Please install Terraform first." -ForegroundColor Red
    exit 1
}

# Check if AWS CLI is installed
if (!(Get-Command aws -ErrorAction SilentlyContinue)) {
    Write-Host "❌ AWS CLI is not installed. Please install AWS CLI first." -ForegroundColor Red
    exit 1
}

# Check AWS credentials
try {
    aws sts get-caller-identity | Out-Null
    Write-Host "✅ AWS credentials configured" -ForegroundColor Green
} catch {
    Write-Host "❌ AWS credentials not configured. Please run 'aws configure' first." -ForegroundColor Red
    exit 1
}

Write-Host "✅ Prerequisites check passed" -ForegroundColor Green

# Check if terraform.tfvars exists
if (!(Test-Path "terraform.tfvars")) {
    Write-Host "⚠️  terraform.tfvars not found. Copying from example..." -ForegroundColor Yellow
    Copy-Item "terraform.tfvars.example" "terraform.tfvars"
    Write-Host "📝 Please edit terraform.tfvars with your specific values, especially:" -ForegroundColor Yellow
    Write-Host "   - key_pair_name: Use your existing EC2 key pair" -ForegroundColor Yellow
    Write-Host "   - aws_region: Your preferred AWS region" -ForegroundColor Yellow
    Write-Host "   - availability_zones: AZs in your region" -ForegroundColor Yellow
    Write-Host ""
    if (!$SkipConfirmation) {
        Read-Host "Press Enter to continue after editing terraform.tfvars"
    }
}

# Initialize Terraform
Write-Host "🔧 Initializing Terraform..." -ForegroundColor Blue
terraform init

# Validate configuration
Write-Host "✅ Validating Terraform configuration..." -ForegroundColor Blue
terraform validate

# Plan deployment
Write-Host "📋 Creating deployment plan..." -ForegroundColor Blue
terraform plan -out=tfplan

Write-Host ""
Write-Host "📊 Deployment Summary:" -ForegroundColor Yellow
Write-Host "----------------------" -ForegroundColor Yellow
Write-Host "This will create:"
Write-Host "- VPC with private subnets"
Write-Host "- VPN Client Endpoint with certificates"
Write-Host "- Application Load Balancer with WAF"
Write-Host "- EC2 Ubuntu instance with web server"
Write-Host "- Aurora MySQL cluster"
Write-Host "- S3 bucket with static pages"
Write-Host "- All security groups and networking"
Write-Host ""

if (!$SkipConfirmation) {
    $confirm = Read-Host "Do you want to proceed with the deployment? (y/N)"
    if ($confirm -notmatch '^[Yy]$') {
        Write-Host "❌ Deployment cancelled" -ForegroundColor Red
        Remove-Item tfplan -ErrorAction SilentlyContinue
        exit 0
    }
}

Write-Host "🚀 Deploying infrastructure..." -ForegroundColor Green
terraform apply tfplan

Write-Host ""
Write-Host "🎉 Deployment completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📋 Important Information:" -ForegroundColor Cyan
Write-Host "========================" -ForegroundColor Cyan

$vpcId = terraform output -raw vpc_id
$vpnEndpointId = terraform output -raw vpn_endpoint_id
$vpnDnsName = terraform output -raw vpn_endpoint_dns_name
$albDnsName = terraform output -raw alb_dns_name
$ec2PrivateIp = terraform output -raw ec2_private_ip
$auroraEndpoint = terraform output -raw aurora_cluster_endpoint
$s3Bucket = terraform output -raw s3_bucket_name

Write-Host "VPC ID: $vpcId"
Write-Host "VPN Endpoint ID: $vpnEndpointId"
Write-Host "VPN DNS Name: $vpnDnsName"
Write-Host "ALB DNS Name: $albDnsName"
Write-Host "EC2 Private IP: $ec2PrivateIp"
Write-Host "Aurora Endpoint: $auroraEndpoint"
Write-Host "S3 Bucket: $s3Bucket"

Write-Host ""
Write-Host "🔑 Next Steps:" -ForegroundColor Yellow
Write-Host "==============" -ForegroundColor Yellow
Write-Host "1. Generate VPN client configuration:"
Write-Host "   aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id $vpnEndpointId --output text > client-config.ovpn"
Write-Host ""
Write-Host "2. Create client certificates (see README.md for details)"
Write-Host ""
Write-Host "3. Install OpenVPN client and import configuration"
Write-Host ""
Write-Host "4. Connect to VPN and access: http://$albDnsName"
Write-Host ""
Write-Host "💡 For detailed instructions, see README.md" -ForegroundColor Blue