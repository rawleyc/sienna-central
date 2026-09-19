resource "tls_private_key" "ssh_private_key" {
    algorithm = "RSA"
    rsa_bits = 4096
}

resource "aws_key_pair" "key_pair" {
    key_name = local.KEY_PAIR_NAME
    public_key = tls_private_key.ssh_private_key.public_key_openssh
    
  
}

resource "local_file" "private_key" {
    content = tls_private_key.ssh_private_key.private_key_openssh
    filename = "${path.module}/SSH_Keys/sienna-central"
    file_permission = 0600
}


resource "aws_subnet" "main" {
  vpc_id                  = data.aws_vpc.main.id
  cidr_block              = "172.31.96.0/24"
  map_public_ip_on_launch = true

  tags = {
    Name = local.SUBNET_NAME
  }
}

resource "aws_security_group" "main" {
  name   = local.SECURITY_GROUP_NAME
  vpc_id = data.aws_vpc.main.id

  ingress {
    description = "SSH from my IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${chomp(data.http.MY_IP.response_body)}/32"]
  }

  ingress {
    description = "Logs from LOBA"
    from_port = 5044
    to_port = 5044
    protocol = "tcp"
    cidr_blocks = [
        "${chomp(data.http.MY_IP.response_body)}/32"
    ]
  }


  ingress {
    description = "HTTP from Cloudflare"
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [
      "103.21.244.0/22",
      "103.22.200.0/22",
      "103.31.4.0/22",
      "104.16.0.0/13",
      "104.24.0.0/14",
      "108.162.192.0/18",
      "131.0.72.0/22",
      "141.101.64.0/18",
      "162.158.0.0/15",
      "172.64.0.0/13",
      "173.245.48.0/20",
      "188.114.96.0/20",
      "190.93.240.0/20",
      "197.234.240.0/22",
      "198.41.128.0/17"
    ]
  }

  egress {
    from_port = 0
    to_port   = 0
    protocol  = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}



resource "aws_instance" "main" {
  ami                         = data.aws_ami.main.id
  instance_type               = local.SIEM_INSTANCE_TYPE
  subnet_id                   = aws_subnet.main.id
  user_data                   = file("${path.module}/user-data.sh")
  user_data_replace_on_change = true
  key_name = aws_key_pair.key_pair.key_name
  security_groups = [aws_security_group.main.id]

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
    encrypted = true
    delete_on_termination = true
  }

  tags = {
    Name = local.INSTANCE_NAME
  }
}

resource "cloudflare_dns_record" "sienna-central" {
  zone_id = var.CLOUDFLARE_ZONE_ID
  name    = "sienna-central"
  type    = "A"
  content = aws_instance.main.public_ip
  ttl     = 1
  proxied = true

}
