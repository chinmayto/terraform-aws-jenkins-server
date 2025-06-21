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