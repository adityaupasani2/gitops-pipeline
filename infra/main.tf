terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Secondary provider for us-west-2
provider "aws" {
  alias  = "west"
  region = "us-west-2"
}
# This file references other files we'll create next
# For now, this just sets up the provider
