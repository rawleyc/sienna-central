output "SIEM_URL" {
  value = "${cloudflare_dns_record.sienna-central.name}"
}

output "SIEM_IP" {
  value = aws_instance.main.public_ip
}
