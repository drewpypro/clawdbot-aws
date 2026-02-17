# =============================================================================
# Variables - Clawdbot AWS Deployment
# =============================================================================

variable "aws_region" {
  type        = string
  description = "AWS region for deployment"
  default     = "us-west-2"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.medium"
}

variable "ssh_public_key" {
  type        = string
  description = "SSH public key for EC2 access"
}

variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GB"
  default     = 30
}

variable "node_version" {
  type        = string
  description = "Node.js version to install"
  default     = "22"
}

variable "subnet_id" {
  type        = string
  description = "Subnet ID for EC2 instance (leave empty for default VPC)"
  default     = ""
}

variable "allowed_ssh_cidrs" {
  type        = list(string)
  description = "CIDR blocks allowed to SSH into the instance"
  default     = [] # Must be set explicitly - no open SSH by default
}

variable "github_repo" {
  type        = string
  description = "GitHub repository (owner/repo) for OIDC federation"
  default     = "drewpypro/clawdbot-aws"
}

variable "state_bucket" {
  type        = string
  description = "S3/R2 bucket name for Terraform state"
  default     = ""
}
