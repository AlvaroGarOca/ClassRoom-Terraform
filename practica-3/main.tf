# VPC con módulo oficial
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.21.0"

  name = "Conv_VPC"

  # Network
  cidr            = "10.0.0.0/16"
  azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"] # Frankfurt
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
}

# Security Group para permitir tráfico HTTP
resource "aws_security_group" "wordpress_sg" {
  name        = "nginx-sg"
  description = "Allow HTTP"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group para el bastion EC2
resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Security group to allow HTTP and SSH access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ip_whitelist
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ec2_sg"
  }
}

resource "aws_security_group" "rds_sg" {
  name   = "rds_sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2_sg.id]
    description     = "Allow MySQL access from EC2"
  }

  ingress {
  from_port       = 3306
  to_port         = 3306
  protocol        = "tcp"
  security_groups = [aws_security_group.wordpress_sg.id]
  description     = "Allow ECS WordPress access"
}

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "wordpress_efs_sg" {
  name   = "wordpress-efs-sg"
  vpc_id = module.vpc.vpc_id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.wordpress_sg.id] # ECS tasks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_key_pair" "ssh-key" {
  key_name   = "server-key"
  public_key = file(var.public_key_location)
}

data "aws_ami" "latest_amazon_linux_image" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn2-ami-kernel-*-hvm-*-x86_64-gp2"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "Conv_EC2" {
  ami = data.aws_ami.latest_amazon_linux_image.id

  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.ssh-key.key_name
  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  subnet_id                   = module.vpc.private_subnets[0]
  associate_public_ip_address = false

  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y mysql
              EOF
}

module "cluster" {
  source = "terraform-aws-modules/rds-aurora/aws"

  name           = "test-aurora-mysql"
  engine         = "aurora-mysql"
  engine_version = "8.0.mysql_aurora.3.09.0"
  instance_class = "db.t4g.medium"
  instances = {
    one = {}
  }

  master_username = "admin"
  master_password = "password"

  vpc_id                 = module.vpc.vpc_id
  db_subnet_group_name   = "aurora-subnet-group"
  create_db_subnet_group = true
  subnets                = module.vpc.private_subnets
  vpc_security_group_ids = [aws_security_group.rds_sg.id]

  storage_encrypted = true
  apply_immediately = true
  skip_final_snapshot = true
  enabled_cloudwatch_logs_exports = []

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }
}

resource "aws_efs_file_system" "wordpress" {
  creation_token = "wordpress-efs"
  encrypted      = true
  tags = {
    Name = "wordpress-efs"
  }
}

locals {
  private_subnet_map = {
    "az1" = module.vpc.private_subnets[0]
    "az2" = module.vpc.private_subnets[1]
    "az3" = module.vpc.private_subnets[2]
  }
}

resource "aws_efs_mount_target" "wordpress" {
  for_each = local.private_subnet_map

  file_system_id  = aws_efs_file_system.wordpress.id
  subnet_id       = each.value
  security_groups = [aws_security_group.wordpress_efs_sg.id]
}


# Creating an ECS cluster
resource "aws_ecs_cluster" "cluster" {
  name = "ecs_terraform_convenio"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Creating an ECS task definition
resource "aws_ecs_task_definition" "task" {
  family                   = "service"
  execution_role_arn       = "arn:aws:iam::414131675413:role/ecsTaskExecutionRole" 
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024

  container_definitions = file("wordpress-convenio.json")

  volume {
    name = "Wordpress-convenio"

    efs_volume_configuration {
      file_system_id = aws_efs_file_system.wordpress.id
      root_directory = "/"

      transit_encryption = "ENABLED"

      authorization_config {
        access_point_id = null
        iam             = "DISABLED"
      }
    }
  }
}

# Creating an ECS service
resource "aws_ecs_service" "service" {
  name             = "service_conv"
  cluster          = aws_ecs_cluster.cluster.id
  task_definition  = aws_ecs_task_definition.task.arn
  desired_count    = 1
  launch_type      = "FARGATE"
  platform_version = "LATEST"

  network_configuration {
    assign_public_ip = true
    security_groups  = [aws_security_group.wordpress_sg.id]
    subnets          = module.vpc.public_subnets
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    serviceName = "service_conv"
  }
}