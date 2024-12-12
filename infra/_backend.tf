# Centralizar o arquivo de controle de estado do terraform
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.70.0"
    }
  }
  backend "s3" {
    bucket = "vicunha-terraform-states"
    key    = "state/sftp-files/infra/terraform.tfstate"
    region = "us-east-2"
  }
}