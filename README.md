ELK SIEM on AWS (Terraform)

Elastic Stack SIEM deployed with Terraform on AWS, with a Windows Server 2025 Core domain controller reporting through Fleet.

Architecture

[diagram: Browser > Cloudflare (443) > Nginx (80) > Kibana (5601, Docker) on EC2; agents > Fleet Server (8220)]

Components
AWS EC2 ARM instance (16 GB, 4 vCPU; ARM chosen for cost), provisioned with Terraform
ELK launched by a user-data script using Docker on ARM
Nginx reverse proxy; DNS A record created by Terraform
Windows Server 2025 Datacenter Core domain controller with Elastic Agents
Deployment

[terraform init / apply steps; what user-data does]

Problems and fixes

| Symptom | Cause | Fix |
| Bad Gateway from Nginx | SELinux blocked proxy network connections | setsebool -P httpd_can_network_connect 1 |
| Amazon AMI missing docker-compose | Not in the AMI | Installed manually in user-data |
| Unhealthy Fleet agents | Single output | Two outputs: Fleet Server to localhost:9200, agents to [agent hostname]:9200 |

Security decisions and known gaps

[what's restricted, what isn't yet]

Detection testing

[link to the Caldera writeup, with detected and missed techniques]

Cost and teardown

[monthly cost estimate, how to destroy]