locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ── VPC ──────────────────────────────────────────────────────────────────────

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-vpc"
  })
}

# ── Internet Gateway ──────────────────────────────────────────────────────────

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-igw"
  })
}

# ── Public Subnets (ALB) ──────────────────────────────────────────────────────

resource "aws_subnet" "public_az1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.aws_region_primary}a"
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-az1"
    Tier = "public"
  })
}

resource "aws_subnet" "public_az2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "${var.aws_region_primary}b"
  map_public_ip_on_launch = false

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-public-az2"
    Tier = "public"
  })
}

# ── Private App Subnets (EC2) ─────────────────────────────────────────────────

resource "aws_subnet" "private_app_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.10.0/24"
  availability_zone = "${var.aws_region_primary}a"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-app-az1"
    Tier = "private-app"
  })
}

resource "aws_subnet" "private_app_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "${var.aws_region_primary}b"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-app-az2"
    Tier = "private-app"
  })
}

# ── Private Data Subnets (Aurora + ElastiCache) ───────────────────────────────

resource "aws_subnet" "private_data_az1" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.20.0/24"
  availability_zone = "${var.aws_region_primary}a"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-data-az1"
    Tier = "private-data"
  })
}

resource "aws_subnet" "private_data_az2" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = "${var.aws_region_primary}b"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-private-data-az2"
    Tier = "private-data"
  })
}

# ── Elastic IPs for NAT Gateways ──────────────────────────────────────────────

resource "aws_eip" "nat_az1" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-eip-az1"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_eip" "nat_az2" {
  domain = "vpc"

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-eip-az2"
  })

  depends_on = [aws_internet_gateway.main]
}

# ── NAT Gateways (one per AZ for HA) ─────────────────────────────────────────

resource "aws_nat_gateway" "az1" {
  allocation_id = aws_eip.nat_az1.id
  subnet_id     = aws_subnet.public_az1.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-az1"
  })

  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "az2" {
  allocation_id = aws_eip.nat_az2.id
  subnet_id     = aws_subnet.public_az2.id

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-nat-az2"
  })

  depends_on = [aws_internet_gateway.main]
}

# ── Route Tables ──────────────────────────────────────────────────────────────

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rt-public"
  })
}

resource "aws_route_table" "private_az1" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.az1.id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rt-private-az1"
  })
}

resource "aws_route_table" "private_az2" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.az2.id
  }

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-rt-private-az2"
  })
}

# ── Route Table Associations ──────────────────────────────────────────────────

resource "aws_route_table_association" "public_az1" {
  subnet_id      = aws_subnet.public_az1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_az2" {
  subnet_id      = aws_subnet.public_az2.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "private_app_az1" {
  subnet_id      = aws_subnet.private_app_az1.id
  route_table_id = aws_route_table.private_az1.id
}

resource "aws_route_table_association" "private_app_az2" {
  subnet_id      = aws_subnet.private_app_az2.id
  route_table_id = aws_route_table.private_az2.id
}

resource "aws_route_table_association" "private_data_az1" {
  subnet_id      = aws_subnet.private_data_az1.id
  route_table_id = aws_route_table.private_az1.id
}

resource "aws_route_table_association" "private_data_az2" {
  subnet_id      = aws_subnet.private_data_az2.id
  route_table_id = aws_route_table.private_az2.id
}

# ── Subnet Groups for Managed Services ───────────────────────────────────────

resource "aws_db_subnet_group" "main" {
  name       = "${local.name_prefix}-db-subnet-group"
  subnet_ids = [aws_subnet.private_data_az1.id, aws_subnet.private_data_az2.id]

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-db-subnet-group"
  })
}

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.name_prefix}-cache-subnet-group"
  subnet_ids = [aws_subnet.private_data_az1.id, aws_subnet.private_data_az2.id]

  tags = var.tags
}

# ── VPC Flow Logs (PCI-DSS requirement) ──────────────────────────────────────

resource "aws_flow_log" "main" {
  vpc_id          = aws_vpc.main.id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_logs.arn
  log_destination = aws_cloudwatch_log_group.vpc_flow_logs.arn

  tags = merge(var.tags, {
    Name = "${local.name_prefix}-flow-logs"
  })
}

resource "aws_cloudwatch_log_group" "vpc_flow_logs" {
  name              = "/aws/vpc/${local.name_prefix}/flow-logs"
  retention_in_days = 365

  tags = var.tags
}

resource "aws_iam_role" "flow_logs" {
  name = "${local.name_prefix}-flow-logs-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "${local.name_prefix}-flow-logs-policy"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams"
      ]
      Resource = "*"
    }]
  })
}
