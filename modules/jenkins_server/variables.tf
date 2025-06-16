variable "common_tags" {}
variable "naming_prefix" {}
variable "instance_type" {}
variable "instance_key" {}

variable "ec2_name" {}
variable "vpc_id" {}
variable "public_subnets" {}


variable "sg_ingress_ports" {
  type = list(object({
    description = string
    port        = number
  }))
  default = [
    {
      description = "Allows HTTP traffic"
      port        = 80
    },
    {
      description = "Allows HTTPS traffic"
      port        = 443
    },
    {
      description = "Allows SSH traffic"
      port        = 22
    },
  ]
}