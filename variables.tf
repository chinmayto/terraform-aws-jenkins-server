variable "aws_region" {
  type        = string
  description = "AWS region to use for resources."
  default     = "us-east-1"
}

variable "aws_azs" {
  type        = list(string)
  description = "AWS Availability Zones"
  default     = ["us-east-1a", "us-east-1b"]
}

variable "enable_dns_hostnames" {
  type        = bool
  description = "Enable DNS hostnames in VPC"
  default     = true
}

variable "vpc_cidr_block_a" {
  type        = string
  description = "Base CIDR Block for VPC A"
  default     = "10.1.0.0/16"
}

variable "vpc_public_subnets_cidr_block" {
  type        = list(string)
  description = "CIDR Block for Public Subnets in VPC"
  default     = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

variable "instance_type" {
  type        = string
  description = "Type for EC2 Instance"
  default     = "t2.medium"
}

variable "sg_ingress_public" {
  type = list(object({
    description = string
    port        = number
  }))
  default = [
    {
      description = "Allows SSH access"
      port        = 22
    },
    {
      description = "Allows HTTP traffic"
      port        = 80
    },
  ]
}

variable "sg_ingress_private" {
  type = list(object({
    description = string
    port        = number
  }))
  default = []
}

variable "naming_prefix" {
  type        = string
  description = "Naming prefix for all resources."
  default     = "CT"
}

variable "environment" {
  type        = string
  description = "Environment for deployment"
  default     = "DEV"
}

variable "instance_key" {
  default = "WorkshopKeyPair"
}