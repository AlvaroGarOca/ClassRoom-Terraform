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

resource "aws_security_group" "ec2_sg" {
  name        = "ec2_sg"
  description = "Security group to allow HTTP and SSH access"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "HTTP from anywhere"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

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
  subnet_id                   = module.vpc.public_subnets[0]
  associate_public_ip_address = true

  user_data = <<-EOF
#!/bin/bash
    exec > /var/log/user-data.log 2>&1

    # Actualizar el sistema
    yum update -y

    # Habilitar e instalar Python 3.8 (disponible en Amazon Linux Extras)
    amazon-linux-extras enable python3.8
    yum install -y git python3.8

    # Instalar NGINX
    amazon-linux-extras enable nginx1
    yum install -y nginx
    systemctl enable nginx
    systemctl start nginx

    # Instalar pip para la nueva versión de Python
    python3.8 -m ensurepip --upgrade
    python3.8 -m pip install --upgrade pip

    # Clonar el repositorio y preparar el sitio con MkDocs
    cd /tmp
    git clone https://github.com/AlvaroGarOca/PrimerMKdocs.git
    cd PrimerMKdocs
    python3.8 -m pip install -r requirements.txt
    python3.8 -m mkdocs build

    # Copiar el sitio a NGINX
    cp -r site/* /usr/share/nginx/html/

    systemctl restart nginx
              EOF
}