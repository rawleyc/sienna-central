data "aws_ami" "main" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn*"]
  }

  filter {
    name = "architecture"
    values = ["arm64"]
  }
}

data "aws_vpc" "main" {
  default = true
}

data "http" "MY_IP" {
  url = "https://checkip.amazonaws.com"
}