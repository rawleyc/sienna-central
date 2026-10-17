variable "CLOUDFLARE_API_TOKEN" {
  type      = string
  sensitive = true
}

variable "CLOUDFLARE_ZONE_ID" {}

variable "AGENTS_SUBDOMAIN" {}

variable "GITHUB_REPO_NAME" {
  type = string
}