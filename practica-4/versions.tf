terraform {
  required_version = "~> 1.11.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  backend "s3" {
    bucket       = "convenio-tfstate"
    key          = "terraform.tfstate"
    region       = "eu-central-1"
    use_lockfile = true
  }
}

provider "aws" {
  region = "eu-central-1"

  default_tags {
    tags = {
      Environment = "Prod"
      Owner       = "Álvaro García Ocaña"
      Project     = "Convenio Terraform"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
  default_tags {
    tags = {
      Environment = "Prod"
      Owner       = "Álvaro García Ocaña"
      Project     = "Convenio Terraform"
    }
  }
}