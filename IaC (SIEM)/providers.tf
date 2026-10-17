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
      source  = "integrations/github"
      version = "~> 6.0"
    }

    elasticstack = {
      source  = "elastic/elasticstack"
      version = "~>0.11"
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

provider "github" {
  token = var.GITHUB_TOKEN
}


provider "elasticstack" {
  elasticsearch {
    endpoints = ["http://${aws_instance.main.public_ip}:9200"]

    username = "elastic"

    password = data.external.remote_elk_password.result["password"]

    insecure = true
  }


}
