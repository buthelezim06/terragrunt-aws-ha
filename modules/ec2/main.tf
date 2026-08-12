locals {
  name = "${var.environment}-app"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "instance" {
  name        = "${local.name}-sg"
  description = "HTTP from the ALB + Docker Swarm cluster traffic between nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "HTTP from ALB (swarm routing mesh answers on every node)"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [var.alb_sg_id]
  }

  # --- Swarm control-plane / gossip / overlay traffic, node-to-node only ---
  ingress {
    description = "Swarm cluster management (raft consensus)"
    from_port   = 2377
    to_port     = 2377
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Swarm node discovery/gossip (TCP)"
    from_port   = 7946
    to_port     = 7946
    protocol    = "tcp"
    self        = true
  }

  ingress {
    description = "Swarm node discovery/gossip (UDP)"
    from_port   = 7946
    to_port     = 7946
    protocol    = "udp"
    self        = true
  }

  ingress {
    description = "Swarm overlay network data path (VXLAN)"
    from_port   = 4789
    to_port     = 4789
    protocol    = "udp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${local.name}-sg" })
}

data "aws_region" "current" {}

# --- IAM: lets nodes hand off the swarm join token via SSM Parameter Store
# instead of needing SSH/direct network access to each other for bootstrap,
# and doubles as SSM Session Manager access for shelling in without a bastion.
resource "aws_iam_role" "instance" {
  name = "${local.name}-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy" "swarm_bootstrap" {
  name = "${local.name}-swarm-bootstrap"
  role = aws_iam_role.instance.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["ssm:PutParameter", "ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:*:*:parameter/${var.environment}/swarm/*"
    }]
  })
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-profile"
  role = aws_iam_role.instance.name
}

# Two (or var.instance_count) fixed instances, spread round-robin across the
# private subnets/AZs passed in so a single AZ failure doesn't take both down.
resource "aws_instance" "this" {
  count                  = var.instance_count
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  subnet_id              = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name
  key_name               = var.key_name

  # Instance 0 becomes the swarm manager and publishes its join token to SSM.
  # Every other instance polls SSM for that token and joins as a worker.
  user_data = templatefile("${path.module}/user_data.sh", {
    environment = var.environment
    region      = data.aws_region.current.name
    is_manager  = count.index == 0 ? "true" : "false"
  })

  tags = merge(var.tags, {
    Name = "${local.name}-${count.index + 1}"
    SwarmRole = count.index == 0 ? "manager" : "worker"
  })
}

resource "aws_lb_target_group_attachment" "this" {
  count            = var.instance_count
  target_group_arn = var.target_group_arn
  target_id        = aws_instance.this[count.index].id
  port             = 80
}
