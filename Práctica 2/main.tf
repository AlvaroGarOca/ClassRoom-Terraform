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
resource "aws_security_group" "nginx_sg" {
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

# Creating an ECS cluster
resource "aws_ecs_cluster" "cluster" {
  name = "ecs_convenio"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

# Creating an ECS task definition
resource "aws_ecs_task_definition" "task" {
  family                   = "service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = 512
  memory                   = 1024

  container_definitions = jsonencode([
    {
      name: "nginx",
      image: "nginx:latest",
      cpu    = 256,
      memory = 512,
      essential: true,
      portMappings: [
        {
          containerPort: 80,
          hostPort: 80,
        },
      ],
    },
  ])
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
    security_groups  = [aws_security_group.nginx_sg.id]
    subnets          = module.vpc.public_subnets
  }

  lifecycle {
    ignore_changes = [task_definition]
  }

  tags = {
    serviceName = "service_conv"
  }
}
