# =============================================================================
# Outputs - Clawdbot AWS Deployment
# =============================================================================

output "instance_id" {
  value       = aws_instance.clawdbot.id
  description = "EC2 instance ID"
}

output "public_ip" {
  value       = aws_instance.clawdbot.public_ip
  description = "Public IP address of the clawdbot instance"
}

output "private_ip" {
  value       = aws_instance.clawdbot.private_ip
  description = "Private IP address of the clawdbot instance"
}

output "ami_id" {
  value       = data.aws_ami.debian.id
  description = "AMI ID used for the instance"
}

output "security_group_id" {
  value       = aws_security_group.clawdbot.id
  description = "Security group ID"
}

output "ssh_command" {
  value       = "ssh -i <your-key> admin@${aws_instance.clawdbot.public_ip}"
  description = "SSH command to connect (Debian uses 'admin' user)"
}

