################################################################################
# Create VPC and components
################################################################################

module "networking" {
  source               = "./modules/networking"
  name                 = "CT-Jenkins-VPC"
  aws_region           = var.aws_region
  vpc_cidr_block       = var.vpc_cidr_block_a #"10.1.0.0/16"
  enable_dns_hostnames = var.enable_dns_hostnames
  aws_azs              = var.aws_azs
  common_tags          = local.common_tags
  naming_prefix        = local.naming_prefix
}


################################################################################
# Create Web Server Instances
################################################################################

module "jenkins_server" {
  source         = "./modules/jenkins_server"
  ec2_name       = "Jenkins-Server"
  instance_type  = var.instance_type
  instance_key   = var.instance_key
  common_tags    = local.common_tags
  naming_prefix  = local.naming_prefix
  vpc_id         = module.networking.vpc_id
  public_subnets = module.networking.public_subnets
  depends_on     = [module.networking]
}


################################################################################
# Create load balancer with target group
################################################################################

module "alb" {
  source         = "./modules/alb"
  aws_region     = var.aws_region
  aws_azs        = var.aws_azs
  common_tags    = local.common_tags
  naming_prefix  = local.naming_prefix
  vpc_id         = module.networking.vpc_id
  public_subnets = module.networking.public_subnets
  instance_ids   = module.jenkins_server.instance_ids
}

