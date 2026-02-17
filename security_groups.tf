# =============================================================================
# Security Groups - Clawdbot EC2
# =============================================================================

resource "aws_security_group" "clawdbot" {
  name        = "clawdbot-sg"
  description = "Security group for Clawdbot EC2 instance"
  vpc_id      = data.aws_vpc.default.id

  tags = {
    Name    = "clawdbot-sg"
    Project = "clawdbot"
  }
}

# --- Ingress Rules ---

# SSH access (restricted to specified CIDRs)
resource "aws_vpc_security_group_ingress_rule" "ssh" {
  for_each = toset(var.allowed_ssh_cidrs)

  security_group_id = aws_security_group.clawdbot.id
  description       = "SSH from ${each.value}"
  from_port         = 22
  to_port           = 22
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value

  tags = {
    Name = "ssh-${each.value}"
  }
}

# --- Egress Rules ---

# HTTPS outbound (API calls, npm, apt, etc.)
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.clawdbot.id
  description       = "HTTPS outbound"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "https-out"
  }
}

# HTTP outbound (apt repos, OCSP, etc.)
resource "aws_vpc_security_group_egress_rule" "http" {
  security_group_id = aws_security_group.clawdbot.id
  description       = "HTTP outbound"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "http-out"
  }
}

# DNS outbound
resource "aws_vpc_security_group_egress_rule" "dns_udp" {
  security_group_id = aws_security_group.clawdbot.id
  description       = "DNS UDP outbound"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "udp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "dns-udp-out"
  }
}

resource "aws_vpc_security_group_egress_rule" "dns_tcp" {
  security_group_id = aws_security_group.clawdbot.id
  description       = "DNS TCP outbound"
  from_port         = 53
  to_port           = 53
  ip_protocol       = "tcp"
  cidr_ipv4         = "0.0.0.0/0"

  tags = {
    Name = "dns-tcp-out"
  }
}
