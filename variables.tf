# AWS Region
variable "aws_region" {
  description = "AWS region where resources will be deployed"
  type        = string
  default     = "us-east-1"
}

# Environment
variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "poc"
}

# VPC Configuration
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

# VPN Configuration
variable "vpn_client_cidr" {
  description = "CIDR block for VPN clients"
  type        = string
  default     = "192.168.0.0/16"
}

# EC2 Configuration
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_pair_name" {
  description = "Name of the EC2 Key Pair"
  type        = string
  default     = "sistemasclinicos-keypair"
}

# Aurora Configuration
variable "aurora_instance_class" {
  description = "Aurora instance class"
  type        = string
  default     = "db.t3.medium"
}

variable "aurora_backup_retention" {
  description = "Aurora backup retention period"
  type        = number
  default     = 7
}

# S3 Configuration
variable "s3_bucket_name" {
  description = "Name for the S3 bucket (will be prefixed with random string)"
  type        = string
  default     = "sistemasclinicos-static-pages"
}

# Common Tags
variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default = {
    "PoC SistemasClinicos" = "true"
    "Project"              = "SistemasClinicos"
    "ManagedBy"           = "Terraform"
  }
}