# =============================================================================
# AWS Provider and VPC Data
# =============================================================================

provider "aws" {
  region = var.aws_region
}

data "aws_vpc" "default" {
  default = true
}
