terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }

    cloudflare = {
      source = "cloudflare/cloudflare"
    }

    http = {
      source = "hashicorp/http"
    }

    github = {
      source = "integrations/github"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "eu-central-1"
}

provider "http" {}

provider "cloudflare" {
  api_token = var.CLOUDFLARE_API_TOKEN
}