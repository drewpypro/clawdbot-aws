# =============================================================================
# EC2 Instance - Clawdbot (OpenClaw AI Assistant)
# Instance Type: t3.medium (2 vCPU, 4 GB RAM)
# =============================================================================

# --- AMI Data Source (Latest Debian 12 Bookworm) ---
data "aws_ami" "debian" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = ["debian-12-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# --- SSH Key Pair ---
resource "aws_key_pair" "clawdbot" {
  key_name   = "clawdbot-key"
  public_key = var.ssh_public_key

  tags = {
    Name    = "clawdbot-key"
    Project = "clawdbot"
  }
}

# --- EC2 Instance ---
resource "aws_instance" "clawdbot" {
  ami                    = data.aws_ami.debian.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.clawdbot.key_name
  vpc_security_group_ids = [aws_security_group.clawdbot.id]
  subnet_id              = data.aws_subnets.default.ids[0]

  root_block_device {
    volume_size           = var.root_volume_size
    volume_type           = "gp3"
    encrypted             = true
    delete_on_termination = true

    tags = {
      Name    = "clawdbot-root"
      Project = "clawdbot"
    }
  }

  user_data = templatefile("${path.module}/userdata.sh", {
    node_version = var.node_version
  })

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required" # IMDSv2 only
    http_put_response_hop_limit = 1
  }

  tags = {
    Name    = "clawdbot"
    Project = "clawdbot"
  }

  lifecycle {
    ignore_changes = [ami] # Don't replace on AMI updates
  }
}
