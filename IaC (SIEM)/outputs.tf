output "SIEM_URL" {
  value = "${cloudflare_dns_record.sienna-central.name}.valdron.dev"
}

output "AGENT_URL" {
  value = "${cloudflare_dns_record.agents.name}.valdron.dev"
  
}

output "SIEM_IP" {
  value = aws_instance.main.public_ip
}
