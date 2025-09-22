# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-20.04-lts-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Random string for unique naming
resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

# ====================================
# VPC and Networking
# ====================================

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpc-sistemasclinicos"
  })
}

# Private subnets only (as requested)
resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  availability_zone = var.availability_zones[count.index]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-private-subnet-${count.index + 1}"
    Type = "Private"
  })
}

# Internet Gateway (needed for NAT Gateway)
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-igw-sistemasclinicos"
  })
}

# Public subnets for NAT Gateway (minimal configuration)
resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id                  = aws_vpc.main.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.environment}-public-subnet-${count.index + 1}"
    Type = "Public"
  })
}

# Elastic IPs for NAT Gateways
resource "aws_eip" "nat" {
  count = length(var.availability_zones)

  domain = "vpc"
  depends_on = [aws_internet_gateway.main]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-nat-eip-${count.index + 1}"
  })
}

# NAT Gateways for private subnet internet access
resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-nat-gw-${count.index + 1}"
  })

  depends_on = [aws_internet_gateway.main]
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-public-rt"
  })
}

# Route table associations for public subnets
resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Route tables for private subnets
resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-private-rt-${count.index + 1}"
  })
}

# Route table associations for private subnets
resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ====================================
# Security Groups
# ====================================

# VPN Client Security Group
resource "aws_security_group" "vpn_client" {
  name_prefix = "${var.environment}-vpn-client-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for VPN clients"

  # Allow all traffic from VPN clients to VPC resources
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [var.vpc_cidr]
  }

  # Allow internet access for VPN clients
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpn-client-sg"
  })
}

# ALB Security Group
resource "aws_security_group" "alb" {
  name_prefix = "${var.environment}-alb-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for Application Load Balancer"

  # Allow HTTP from VPN clients only
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  # Allow HTTPS from VPN clients only
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  # Allow outbound to private subnets (where EC2 instances are)
  egress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [for subnet in aws_subnet.private : subnet.cidr_block]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-alb-sg"
  })
}

# EC2 Security Group
resource "aws_security_group" "ec2" {
  name_prefix = "${var.environment}-ec2-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for EC2 instances"

  # Allow SSH from VPN clients
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ec2-sg"
  })
}

# Aurora Security Group
resource "aws_security_group" "aurora" {
  name_prefix = "${var.environment}-aurora-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for Aurora MySQL cluster"

  # Allow MySQL from EC2 instances
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }

  # Allow MySQL from VPN clients (for administration)
  ingress {
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [var.vpn_client_cidr]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-aurora-sg"
  })
}

# VPN Endpoint Security Group
resource "aws_security_group" "vpn_endpoint" {
  name_prefix = "${var.environment}-vpn-endpoint-"
  vpc_id      = aws_vpc.main.id
  description = "Security group for VPN endpoint"

  # Allow VPN traffic
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 1194
    to_port     = 1194
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpn-endpoint-sg"
  })
}

# Security Group Rule to allow ALB traffic to EC2 (added separately to avoid circular dependency)
resource "aws_security_group_rule" "alb_to_ec2" {
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  security_group_id        = aws_security_group.ec2.id
  description              = "Allow HTTP from ALB"
}

# ====================================
# TLS Certificates for VPN
# ====================================

# Create a private key for server certificate
resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create a self-signed server certificate for VPN
resource "tls_self_signed_cert" "server" {
  private_key_pem = tls_private_key.server.private_key_pem

  subject {
    common_name  = "vpn.sistemasclinicos.local"
    organization = "Sofre Digital SA"
  }

  validity_period_hours = 8760 # 1 year

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "server_auth",
  ]
}

# Create a private key for client certificate
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Create a self-signed client root certificate for VPN
resource "tls_self_signed_cert" "client_root" {
  private_key_pem = tls_private_key.client.private_key_pem

  subject {
    common_name  = "vpn-client-ca.sistemasclinicos.local"
    organization = "Sofre Digital SA"
  }

  validity_period_hours = 8760 # 1 year
  is_ca_certificate     = true

  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "cert_signing",
  ]
}

# Import server certificate to ACM
resource "aws_acm_certificate" "server" {
  private_key      = tls_private_key.server.private_key_pem
  certificate_body = tls_self_signed_cert.server.cert_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpn-server-cert"
  })
}

# Import client root certificate to ACM
resource "aws_acm_certificate" "client_root" {
  certificate_body = tls_self_signed_cert.client_root.cert_pem
  private_key      = tls_private_key.client.private_key_pem

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpn-client-root-cert"
  })
}

# ====================================
# CloudWatch Log Group for VPN
# ====================================

resource "aws_cloudwatch_log_group" "vpn_logs" {
  name              = "/aws/clientvpn/${var.environment}-sistemasclinicos"
  retention_in_days = 7

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpn-logs"
  })
}

resource "aws_cloudwatch_log_stream" "vpn_logs" {
  name           = "${var.environment}-vpn-log-stream"
  log_group_name = aws_cloudwatch_log_group.vpn_logs.name
}

# ====================================
# VPN Client Endpoint
# ====================================

resource "aws_ec2_client_vpn_endpoint" "main" {
  description            = "VPN endpoint for SistemasClinicos PoC"
  server_certificate_arn = aws_acm_certificate.server.arn
  client_cidr_block      = var.vpn_client_cidr
  vpc_id                 = aws_vpc.main.id
  security_group_ids     = [aws_security_group.vpn_endpoint.id]
  
  # Split tunnel to allow direct internet access
  split_tunnel = true
  
  # Session timeout
  session_timeout_hours = 8

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.client_root.arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn_logs.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn_logs.name
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpn-endpoint"
  })
}

# Associate VPN endpoint with private subnets
resource "aws_ec2_client_vpn_network_association" "main" {
  count = length(aws_subnet.private)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  subnet_id              = aws_subnet.private[count.index].id
}

# Authorization rule to allow VPN clients access to VPC
resource "aws_ec2_client_vpn_authorization_rule" "vpc_access" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  target_network_cidr    = aws_vpc.main.cidr_block
  authorize_all_groups   = true
  description            = "Allow VPN clients access to VPC"
}

# Authorization rule to allow internet access through VPN
resource "aws_ec2_client_vpn_authorization_rule" "internet_access" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  target_network_cidr    = "0.0.0.0/0"
  authorize_all_groups   = true
  description            = "Allow VPN clients internet access"
}

# Route for VPC traffic
resource "aws_ec2_client_vpn_route" "vpc" {
  count = length(aws_subnet.private)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  destination_cidr_block = aws_vpc.main.cidr_block
  target_vpc_subnet_id   = aws_subnet.private[count.index].id
  description            = "Route to VPC from VPN clients"
}

# ====================================
# S3 Bucket for Static Error Page
# ====================================

resource "aws_s3_bucket" "static_pages" {
  bucket = "${var.s3_bucket_name}-${random_string.suffix.result}"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-static-pages-bucket"
  })
}

resource "aws_s3_bucket_versioning" "static_pages" {
  bucket = aws_s3_bucket.static_pages.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "static_pages" {
  bucket = aws_s3_bucket.static_pages.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "static_pages" {
  bucket = aws_s3_bucket.static_pages.id

  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_website_configuration" "static_pages" {
  bucket = aws_s3_bucket.static_pages.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_bucket_policy" "static_pages" {
  bucket = aws_s3_bucket.static_pages.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PublicReadGetObject"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.static_pages.arn}/*"
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.static_pages]
}

# Upload VPN requirement page
resource "aws_s3_object" "vpn_required_page" {
  bucket       = aws_s3_bucket.static_pages.id
  key          = "vpn-required.html"
  content_type = "text/html"
  content = <<EOF
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPN Required - SistemasClinicos</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin: 0;
            padding: 0;
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 15px 35px rgba(0, 0, 0, 0.1);
            text-align: center;
            max-width: 500px;
        }
        .logo {
            font-size: 24px;
            font-weight: bold;
            color: #333;
            margin-bottom: 20px;
        }
        .icon {
            font-size: 64px;
            margin-bottom: 20px;
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        p {
            color: #666;
            line-height: 1.6;
            margin-bottom: 20px;
        }
        .btn {
            background: #667eea;
            color: white;
            padding: 12px 24px;
            border: none;
            border-radius: 5px;
            text-decoration: none;
            display: inline-block;
            margin-top: 20px;
            font-weight: bold;
        }
        .btn:hover {
            background: #5a6fd8;
        }
        .requirements {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 5px;
            margin-top: 20px;
            text-align: left;
        }
        .requirements h3 {
            margin-top: 0;
            color: #333;
        }
        .requirements ol {
            color: #666;
            padding-left: 20px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">SistemasClinicos</div>
        <div class="icon">🔒</div>
        <h1>Acceso Restringido</h1>
        <p>Para acceder a los recursos de SistemasClinicos, debe estar conectado a la VPN corporativa.</p>
        
        <div class="requirements">
            <h3>Para conectarse a la VPN:</h3>
            <ol>
                <li>Descargue el cliente OpenVPN desde <a href="https://openvpn.net/client-connect-vpn-for-windows/" target="_blank">openvpn.net</a></li>
                <li>Obtenga el archivo de configuración de su administrador de sistemas</li>
                <li>Importe la configuración en el cliente OpenVPN</li>
                <li>Conéctese a la VPN e intente acceder nuevamente</li>
            </ol>
        </div>
        
        <p><strong>¿Necesita ayuda?</strong><br>
        Contacte al administrador de sistemas para obtener acceso a la VPN.</p>
        
        <a href="#" onclick="window.location.reload()" class="btn">Reintentar Conexión</a>
    </div>
</body>
</html>
EOF

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpn-required-page"
  })
}

# ====================================
# WAF Configuration
# ====================================

resource "aws_wafv2_web_acl" "main" {
  name  = "${var.environment}-sistemasclinicos-waf"
  scope = "REGIONAL"

  default_action {
    block {}
  }

  # Rule to allow traffic from VPN client CIDR
  rule {
    name     = "AllowVPNClients"
    priority = 1

    action {
      allow {}
    }

    statement {
      ip_set_reference_statement {
        arn = aws_wafv2_ip_set.vpn_clients.arn
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "AllowVPNClientsRule"
      sampled_requests_enabled   = true
    }
  }

  # Rule to block all other traffic
  rule {
    name     = "BlockNonVPNTraffic"
    priority = 2

    action {
      block {}
    }

    statement {
      not_statement {
        statement {
          ip_set_reference_statement {
            arn = aws_wafv2_ip_set.vpn_clients.arn
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "BlockNonVPNTrafficRule"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "SistemasClinicosWAF"
    sampled_requests_enabled   = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-sistemasclinicos-waf"
  })
}

resource "aws_wafv2_ip_set" "vpn_clients" {
  name               = "${var.environment}-vpn-clients-ipset"
  scope              = "REGIONAL"
  ip_address_version = "IPV4"
  addresses          = [var.vpn_client_cidr]

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpn-clients-ipset"
  })
}

# ====================================
# Application Load Balancer
# ====================================

resource "aws_lb" "main" {
  name               = "${var.environment}-sistemasclinicos-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.private[*].id

  enable_deletion_protection = false

  tags = merge(var.common_tags, {
    Name = "${var.environment}-sistemasclinicos-alb"
  })
}

# Target group for EC2 instance
resource "aws_lb_target_group" "ec2" {
  name     = "${var.environment}-ec2-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/"
    matcher             = "200"
    port                = "traffic-port"
    protocol            = "HTTP"
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ec2-target-group"
  })
}

# ALB Listener with custom rules
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  # Default action: redirect to VPN required page
  default_action {
    type = "redirect"

    redirect {
      host        = aws_s3_bucket_website_configuration.static_pages.website_endpoint
      path        = "/vpn-required.html"
      port        = "80"
      protocol    = "HTTP"
      status_code = "HTTP_302"
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-alb-listener"
  })
}

# Listener rule for VPN clients
resource "aws_lb_listener_rule" "vpn_clients" {
  listener_arn = aws_lb_listener.main.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ec2.arn
  }

  condition {
    source_ip {
      values = [var.vpn_client_cidr]
    }
  }

  tags = merge(var.common_tags, {
    Name = "${var.environment}-vpn-clients-rule"
  })
}

# Associate WAF with ALB
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}

# ====================================
# IAM Role for EC2 Instance
# ====================================

resource "aws_iam_role" "ec2" {
  name = "${var.environment}-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.common_tags, {
    Name = "${var.environment}-ec2-role"
  })
}

resource "aws_iam_role_policy" "ec2_cloudwatch" {
  name = "${var.environment}-ec2-cloudwatch-policy"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "cloudwatch:PutMetricData"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.environment}-ec2-profile"
  role = aws_iam_role.ec2.name
}

# ====================================
# EC2 Instance
# ====================================

resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.private[0].id
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = base64encode(<<-EOF
              #!/bin/bash
              apt-get update
              apt-get install -y apache2 mysql-client-core-8.0
              
              # Start Apache
              systemctl start apache2
              systemctl enable apache2
              
              # Create a simple HTML page
              cat > /var/www/html/index.html << 'HTML'
<!DOCTYPE html>
<html lang="es">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>SistemasClinicos - PoC</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            margin: 0;
            padding: 20px;
            min-height: 100vh;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 10px;
            box-shadow: 0 15px 35px rgba(0, 0, 0, 0.1);
            max-width: 800px;
            margin: 0 auto;
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        .logo {
            font-size: 32px;
            font-weight: bold;
            color: #333;
            margin-bottom: 10px;
        }
        .status {
            background: #d4edda;
            border: 1px solid #c3e6cb;
            color: #155724;
            padding: 12px 20px;
            border-radius: 5px;
            margin: 20px 0;
        }
        .info-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin-top: 30px;
        }
        .info-card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 8px;
            border-left: 4px solid #667eea;
        }
        .info-card h3 {
            margin-top: 0;
            color: #333;
        }
        .info-card p {
            color: #666;
            margin: 0;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <div class="logo">SistemasClinicos</div>
            <h1>Bienvenido al Sistema PoC</h1>
        </div>
        
        <div class="status">
            ✅ Conectado exitosamente a través de VPN
        </div>
        
        <p>Este es el entorno de prueba de concepto (PoC) para SistemasClinicos. 
        Su conexión ha sido validada y tiene acceso a los recursos privados.</p>
        
        <div class="info-grid">
            <div class="info-card">
                <h3>🌐 Conexión VPN</h3>
                <p>Conectado a través de AWS Client VPN</p>
            </div>
            <div class="info-card">
                <h3>🔒 Seguridad</h3>
                <p>Protegido por AWS WAF y Security Groups</p>
            </div>
            <div class="info-card">
                <h3>🖥️ Servidor</h3>
                <p>Ubuntu 20.04 LTS en AWS EC2</p>
            </div>
            <div class="info-card">
                <h3>🗄️ Base de Datos</h3>
                <p>Aurora MySQL en red privada</p>
            </div>
        </div>
        
        <p style="margin-top: 30px; text-align: center; color: #666;">
            <strong>Proyecto:</strong> PoC SistemasClinicos | 
            <strong>Infraestructura:</strong> AWS + Terraform
        </p>
    </div>
</body>
</html>
HTML

              # Set correct permissions
              chown -R www-data:www-data /var/www/html
              chmod -R 755 /var/www/html
              
              # Restart Apache
              systemctl restart apache2
              EOF
  )

  tags = merge(var.common_tags, {
    Name = "${var.environment}-web-server"
  })
}

# Attach EC2 instance to target group
resource "aws_lb_target_group_attachment" "ec2" {
  target_group_arn = aws_lb_target_group.ec2.arn
  target_id        = aws_instance.web.id
  port             = 80
}

# ====================================
# Aurora MySQL Cluster
# ====================================

# Create DB subnet group
resource "aws_db_subnet_group" "aurora" {
  name       = "${var.environment}-aurora-subnet-group"
  subnet_ids = aws_subnet.private[*].id

  tags = merge(var.common_tags, {
    Name = "${var.environment}-aurora-subnet-group"
  })
}

# Generate random password for Aurora
resource "random_password" "aurora_master" {
  length  = 16
  special = true
}

# Store Aurora password in AWS Secrets Manager
resource "aws_secretsmanager_secret" "aurora_password" {
  name        = "${var.environment}-aurora-master-password"
  description = "Aurora MySQL master password for SistemasClinicos PoC"

  tags = merge(var.common_tags, {
    Name = "${var.environment}-aurora-password"
  })
}

resource "aws_secretsmanager_secret_version" "aurora_password" {
  secret_id = aws_secretsmanager_secret.aurora_password.id
  secret_string = jsonencode({
    username = "admin"
    password = random_password.aurora_master.result
  })
}

# Aurora MySQL cluster
resource "aws_rds_cluster" "aurora" {
  cluster_identifier              = "${var.environment}-sistemasclinicos-aurora"
  engine                         = "aurora-mysql"
  engine_version                 = "8.0.mysql_aurora.3.02.0"
  database_name                  = "sistemasclinicos"
  master_username                = "admin"
  master_password                = random_password.aurora_master.result
  backup_retention_period        = var.aurora_backup_retention
  preferred_backup_window        = "03:00-04:00"
  preferred_maintenance_window   = "sun:04:00-sun:05:00"
  db_subnet_group_name          = aws_db_subnet_group.aurora.name
  vpc_security_group_ids        = [aws_security_group.aurora.id]
  storage_encrypted             = true
  skip_final_snapshot           = true
  deletion_protection           = false

  tags = merge(var.common_tags, {
    Name = "${var.environment}-aurora-cluster"
  })
}

# Aurora cluster instances
resource "aws_rds_cluster_instance" "aurora" {
  identifier           = "${var.environment}-aurora-instance-1"
  cluster_identifier   = aws_rds_cluster.aurora.id
  instance_class       = var.aurora_instance_class
  engine               = aws_rds_cluster.aurora.engine
  engine_version       = aws_rds_cluster.aurora.engine_version
  publicly_accessible = false

  tags = merge(var.common_tags, {
    Name = "${var.environment}-aurora-instance-1"
  })
}