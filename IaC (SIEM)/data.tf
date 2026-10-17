data "aws_ami" "main" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn*"]
  }

  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

data "aws_vpc" "main" {
  default = true
}

data "http" "MY_IP" {
  url = "https://checkip.amazonaws.com"
}


data "external" "remote_elk_password" {
  program = ["powershell", "-Command", <<EOF
    $ip = "${aws_instance.main.public_ip}"
    $keyPath = "C:\Users\chiru\OneDrive\Documents\Programming Projects\sienna-central\IaC (SIEM)\SSH_Keys\sienna-central"
    
    # 1. Retry loop to wait until the SSH port (22) is open and credentials file is accessible
    $maxAttempts = 15
    $attempt = 1
    $connected = $false
    $file_content = ""

    while (-not $connected -and $attempt -le $maxAttempts) {
        try {
            $file_content = (ssh -i $keyPath -o ConnectTimeout=5 -o StrictHostKeyChecking=no ec2-user@$ip "sudo cat /root/sienna-central-credentials.txt" 2>$null | Out-String).Trim()
            if ($file_content) {
                $connected = $true
            } else {
                throw "Empty response"
            }
        } catch {
            Start-Sleep -Seconds 5
            $attempt++
        }
    }

    if (-not $connected) {
        Write-Error "Timed out waiting for SSH daemon or credentials file to become available on the EC2 instance."
        exit 1
    }
    
    # 2. Advanced Regex matching for your specific file structure
    if ($file_content -match '(?s)Elastic user:.*?Password:\s*([^\s\r\n]+)') {
        $elastic_pass = $Matches[1]
    } else {
        Write-Error "Could not parse Elastic password from the file structure."
        exit 1
    }

    # 3. Wait until the Elasticsearch Docker container wakes up and begins routing requests on port 9200
    $containerReady = $false
    $dockerAttempts = 60  # 60 attempts * 5 seconds = Up to 5 minutes for Docker and Elasticsearch startup
    $dAttempt = 1

    while (-not $containerReady -and $dAttempt -le $dockerAttempts) {
        try {
            # Execute a curl check locally inside the EC2 server via SSH.
            $response = (ssh -i $keyPath -o StrictHostKeyChecking=no ec2-user@$ip "curl -s -o /dev/null -w '%%{http_code}' http://localhost:9200" 2>$null | Out-String).Trim()

            # Accepts 200 (Healthy), 401 (Auth Alive), or 301/302 (Redirects) as ready metrics
            if ($response -match '^(200|301|302|401)$') {
                $containerReady = $true
            } else {
                throw "Container initializing"
            }
        } catch {
            Start-Sleep -Seconds 5
            $dAttempt++
        }
    }

    if (-not $containerReady) {
        Write-Error "Timed out waiting for Elasticsearch Docker container to bind to port 9200."
        exit 1
    }
    
    # 4. Output as clean compressed JSON format back to Terraform
    @{ password = $elastic_pass } | ConvertTo-Json -Compress
EOF
  ]

  depends_on = [aws_instance.main]
}
