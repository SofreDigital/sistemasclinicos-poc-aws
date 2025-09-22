#!/bin/bash

# SistemasClinicos PoC Deployment Script
# This script helps deploy the AWS infrastructure using Terraform

set -e

echo "🚀 SistemasClinicos PoC - AWS Infrastructure Deployment"
echo "=================================================="

# Check if terraform is installed
if ! command -v terraform &> /dev/null; then
    echo "❌ Terraform is not installed. Please install Terraform first."
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "❌ AWS CLI is not installed. Please install AWS CLI first."
    exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS credentials not configured. Please run 'aws configure' first."
    exit 1
fi

echo "✅ Prerequisites check passed"

# Check if terraform.tfvars exists
if [ ! -f "terraform.tfvars" ]; then
    echo "⚠️  terraform.tfvars not found. Copying from example..."
    cp terraform.tfvars.example terraform.tfvars
    echo "📝 Please edit terraform.tfvars with your specific values, especially:"
    echo "   - key_pair_name: Use your existing EC2 key pair"
    echo "   - aws_region: Your preferred AWS region"
    echo "   - availability_zones: AZs in your region"
    echo ""
    read -p "Press Enter to continue after editing terraform.tfvars..."
fi

# Initialize Terraform
echo "🔧 Initializing Terraform..."
terraform init

# Validate configuration
echo "✅ Validating Terraform configuration..."
terraform validate

# Plan deployment
echo "📋 Creating deployment plan..."
terraform plan -out=tfplan

echo ""
echo "📊 Deployment Summary:"
echo "----------------------"
echo "This will create:"
echo "- VPC with private subnets"
echo "- VPN Client Endpoint with certificates"
echo "- Application Load Balancer with WAF"
echo "- EC2 Ubuntu instance with web server"
echo "- Aurora MySQL cluster"
echo "- S3 bucket with static pages"
echo "- All security groups and networking"
echo ""

read -p "Do you want to proceed with the deployment? (y/N): " confirm

if [[ $confirm =~ ^[Yy]$ ]]; then
    echo "🚀 Deploying infrastructure..."
    terraform apply tfplan
    
    echo ""
    echo "🎉 Deployment completed successfully!"
    echo ""
    echo "📋 Important Information:"
    echo "========================"
    
    echo "VPC ID: $(terraform output -raw vpc_id)"
    echo "VPN Endpoint ID: $(terraform output -raw vpn_endpoint_id)"
    echo "VPN DNS Name: $(terraform output -raw vpn_endpoint_dns_name)"
    echo "ALB DNS Name: $(terraform output -raw alb_dns_name)"
    echo "EC2 Private IP: $(terraform output -raw ec2_private_ip)"
    echo "Aurora Endpoint: $(terraform output -raw aurora_cluster_endpoint)"
    echo "S3 Bucket: $(terraform output -raw s3_bucket_name)"
    
    echo ""
    echo "🔑 Next Steps:"
    echo "=============="
    echo "1. Generate VPN client configuration:"
    echo "   aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id $(terraform output -raw vpn_endpoint_id) --output text > client-config.ovpn"
    echo ""
    echo "2. Create client certificates (see README.md for details)"
    echo ""
    echo "3. Install OpenVPN client and import configuration"
    echo ""
    echo "4. Connect to VPN and access: http://$(terraform output -raw alb_dns_name)"
    echo ""
    echo "💡 For detailed instructions, see README.md"
    
else
    echo "❌ Deployment cancelled"
    rm -f tfplan
    exit 0
fi