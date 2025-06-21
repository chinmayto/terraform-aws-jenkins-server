# Deploying Jenkins on EC2 for CI/CD Pipelines

Here we will walk through the process of provisioning a Jenkins server on an Amazon EC2 instance within a public subnet. This setup lays the foundation for building robust CI/CD pipelines on AWS. We will use Terraform to automate infrastructure provisioning and install Jenkins for orchestration.

### Architecture Overview
Here is the architecture we will be dealing with. The purpose of this is only to have a jenkins server running, the architecture may not be ideal.

![alt text](/images/architecture.png)

### Step 1: Create Networking Components

We will create a VPC with a public subnet, internet gateway and application load balancer along with custom domain with ACM certificate validation

```terraform
################################################################################
# Get list of available AZs
################################################################################
data "aws_availability_zones" "available_zones" {
  state = "available"
}

################################################################################
# Create the VPC
################################################################################
resource "aws_vpc" "app_vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = var.enable_dns_hostnames

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-${var.name}"
  })
}

################################################################################
# Create the internet gateway
################################################################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.app_vpc.id

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-igw"
  })
}

################################################################################
# Create the public subnets
################################################################################
resource "aws_subnet" "public_subnets" {
  vpc_id = aws_vpc.app_vpc.id

  count             = 2
  cidr_block        = cidrsubnet(var.vpc_cidr_block, 8, count.index)
  availability_zone = data.aws_availability_zones.available_zones.names[count.index]

  map_public_ip_on_launch = true # This makes public subnet

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-pubsubnet-${count.index + 1}"
  })
}

################################################################################
# Create the public route table
################################################################################
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.app_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-pub-rtable"
  })

}

################################################################################
# Assign the public route table to the public subnet
################################################################################
resource "aws_route_table_association" "public_rt_asso" {
  count          = 2
  subnet_id      = element(aws_subnet.public_subnets[*].id, count.index)
  route_table_id = aws_route_table.public_route_table.id
}

```

```terraform
################################################################################
# Define the security group for the Load Balancer
################################################################################
resource "aws_security_group" "aws-sg-load-balancer" {
  description = "Allow incoming connections for load balancer"
  vpc_id      = var.vpc_id
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow incoming HTTP connections"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-sg-alb"
  })
}

################################################################################
# Create application load balancer
################################################################################
resource "aws_lb" "aws-application_load_balancer" {
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.aws-sg-load-balancer.id]

  subnets                    = tolist(var.public_subnets)
  enable_deletion_protection = false

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-alb"
  })
}
################################################################################
# create target group for ALB
################################################################################
resource "aws_lb_target_group" "alb_target_group" {
  target_type = "instance"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id

  health_check {
    enabled             = true
    interval            = 60
    path                = "/login"
    timeout             = 30
    matcher             = 200
    healthy_threshold   = 5
    unhealthy_threshold = 5
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-alb-tg"
  })
}

################################################################################
# Create ACM Certificate with suggested domain name
################################################################################
resource "aws_acm_certificate" "mycert_acm" {
  domain_name               = "jenkins.${var.domain_name}"
  subject_alternative_names = ["*.jenkins.${var.domain_name}"]

  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}
################################################################################
# Route53 resources to perform DNS auto validation
################################################################################
data "aws_route53_zone" "selected_zone" {
  name         = var.domain_name
  private_zone = false
}

resource "aws_route53_record" "cert_validation_record" {
  for_each = {
    for dvo in aws_acm_certificate.mycert_acm.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_route53_zone.selected_zone.zone_id
}

################################################################################
# DNS valiadtion of Certificate
################################################################################
resource "aws_acm_certificate_validation" "cert_validation" {
  timeouts {
    create = "5m"
  }
  certificate_arn         = aws_acm_certificate.mycert_acm.arn
  validation_record_fqdns = [for record in aws_route53_record.cert_validation_record : record.fqdn]
}


################################################################################
# create a listener on port 80 with redirect action
################################################################################
resource "aws_lb_listener" "alb_http_listener" {
  load_balancer_arn = aws_lb.aws-application_load_balancer.id
  port              = 443
  protocol          = "HTTPS"

  certificate_arn = aws_acm_certificate_validation.cert_validation.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_target_group.id
  }
}

################################################################################
# Target Group Attachment with Instance
################################################################################
resource "aws_alb_target_group_attachment" "tgattachment" {
  count            = length(var.instance_ids)
  target_group_arn = aws_lb_target_group.alb_target_group.arn
  target_id        = element(var.instance_ids, count.index)
}

################################################################################
# Create Route53 Record
################################################################################
resource "aws_route53_record" "route53_A_record" {
  zone_id = data.aws_route53_zone.selected_zone.zone_id
  name    = "jenkins.${var.domain_name}"
  type    = "A"
  alias {
    name                   = aws_lb.aws-application_load_balancer.dns_name
    zone_id                = aws_lb.aws-application_load_balancer.zone_id
    evaluate_target_health = true
  }
}
```

### Step 2: Launch EC2 Instance and Install Jenkins

Here we will create an EC2 instance in public subnet.

```terraform
################################################################################
# Get latest Ubuntu AMI
################################################################################
data "aws_ami" "ubuntu22" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

################################################################################
# Create the security group for EC2 Jenkins Server
################################################################################
resource "aws_security_group" "ec2_security_group" {
  description = "Allow traffic for EC2 Jenkins Server"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.sg_ingress_ports
    iterator = sg_ingress

    content {
      description = sg_ingress.value["description"]
      from_port   = sg_ingress.value["port"]
      to_port     = sg_ingress.value["port"]
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-sg-jenkins-server"
  })
}

resource "aws_security_group" "ec2_jenkins_port_8080" {
  description = "Enable the Port 8080 for jenkins"
  vpc_id      = var.vpc_id

  # ssh for terraform remote exec
  ingress {
    description = "Allow 8080 port to access jenkins"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
  }

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-sg-jenkins-server-8080"
  })
}


################################################################################
# Create the Linux EC2 Web server
################################################################################
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu22.id
  instance_type          = var.instance_type
  key_name               = var.instance_key
  vpc_security_group_ids = [aws_security_group.ec2_security_group.id, aws_security_group.ec2_jenkins_port_8080.id]

  # count     = length(var.public_subnets)
  # subnet_id = element(var.public_subnets, count.index)
  subnet_id = var.public_subnets[0]


  user_data = file("./modules/jenkins_server/jenkins_installer.tpl")

  tags = merge(var.common_tags, {
    Name = "${var.naming_prefix}-Jenkins-Server"
  })
}
```

Following is the userdata script to install Jenkins and AWS CLI on launched EC2 instance
```shell
#!/bin/bash
sudo apt update
yes | sudo apt install fontconfig openjdk-21-jre unzip


echo "Waiting for 30 seconds before installing the jenkins package..."
sleep 30
sudo wget -O /etc/apt/keyrings/jenkins-keyring.asc \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc]" \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt-get update
yes | sudo apt-get install jenkins
sleep 30

echo "Waiting for 30 seconds before installing the AWS CLI..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

echo "Jenkins and AWS CLI installed on this server..."
```

### Step 3: First-Time Jenkins Login & Plugin Installation

Visit https://jenkins.chinmayto.com where we have defned custom domain.

![alt text](/images/jenkins_init_1.png)

Retrieve the initial password from EC2 instance:
```sh
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```
![alt text](/images/jenkins_init_2.png)

![alt text](/images/jenkins_init_3.png)

Install the following plugins manually via Manage Jenkins > Plugin Manager > Available.
AWS CloudFormation
AWS Credentials

![alt text](/images/jenkins_init_4.png)

![alt text](/images/jenkins_init_5.png)

![alt text](/images/jenkins_init_6.png)

Setup is now complete and we are ready to use it

![alt text](/images/jenkins_init_7.png)

### Cleanup
To avoid unnecessary AWS billing, destroy the infrastructure when not in use:
```terraform
terraform destroy -auto-approve
```

### Conclusion
You’ve now set up a fully functional Jenkins server on AWS using Terraform. This forms the base for creating CI/CD pipelines for your applications. In upcoming posts, we’ll explore how to connect this Jenkins setup with GitHub and deploy applications to AWS services.


## References
GitHub Repo: https://github.com/chinmayto/terraform-aws-jenkins-server

Jenkins Installation: https://www.jenkins.io/doc/book/installing/linux/