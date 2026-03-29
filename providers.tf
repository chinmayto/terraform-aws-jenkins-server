terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket                     = "chinmayto-terraform-state-bucket-1755526674"
    key                        = "jenkins-server/terraform.tfstate"
    region                     = "us-east-1"
    encrypt                    = true
    use_lockfile               = true
    skip_requesting_account_id = false
  }
}

################################################################################
# Configure the AWS Provider
################################################################################
provider "aws" {
  region = var.aws_region
}
