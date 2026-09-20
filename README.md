Setting up a SIEM system.
ELK sitting on AWS. < Provisioned instance using terraform (16GB 4vCPU ARM instance {ARM is cheaper})>
Exported private key for SSH troubleshooting of user-data script.
User Data script logging >> cloud-init log
AMAZON AMI did not have linux did not have docker-compose (manually downloaded)
So far created a user-data script to lanuch ELK using docker on ARM arch. 
Used Nginx proxy to accept traffic on port 80 then redirect to 5601 on docker container
Used terraform to create an A record in domain DNS and point it towards the EC2 SIEM instance
Browser (443) > Cloudflare (80) > SIEM(EC2)
Was getting constant Bad gateway errors, had to allow NGINX to make network connections using "setsebool -P httpd_can_network_connect 1"
Setup ELK security (2 kibana users and password generated using openssl) stored in root

Setting up the DC using Windows Server 2025 Datacenter Core (less resource usage)
Opened agent traffic to port 8220 via cloudflare (UNPROXIED)
Unhealthy agents .... needed to create two outputs ... 1 for Fleet Server > localhost:9200 ... 2 For Agents > agents.vladron.dev:9200