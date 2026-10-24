[CmdletBinding()]
param(
    [switch]$AutoApprove
)

$ErrorActionPreference = "Stop"
$iacDirectory = $PSScriptRoot
$keyPath = Join-Path $iacDirectory "SSH_Keys\sienna-central"

Push-Location $iacDirectory
try {
    function Invoke-Terraform {
        param(
            [Parameter(Mandatory = $true)]
            [string[]]$Arguments
        )

        & terraform @Arguments
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform failed with exit code $LASTEXITCODE."
        }
    }

    function Get-StateValue {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Address,
            [Parameter(Mandatory = $true)]
            [string]$Property
        )

        $state = terraform state show $Address 2>$null
        if ($LASTEXITCODE -ne 0) {
            throw "Could not read $Address from Terraform state."
        }

        $match = $state | Select-String "^\s*$Property\s*=\s*`"([^`"]+)`""
        if (-not $match) {
            throw "Could not find '$Property' in Terraform state for $Address."
        }

        return $match.Matches[0].Groups[1].Value
    }

    if (-not (Test-Path -LiteralPath $keyPath -PathType Leaf)) {
        throw "SSH private key not found at $keyPath."
    }

    $ip = Get-StateValue -Address "aws_instance.main" -Property "public_ip"
    $keyId = Get-StateValue -Address "elasticstack_elasticsearch_security_api_key.github_dac_key" -Property "key_id"

    Write-Host "Reading the Elasticsearch password from $ip..."
    $credentials = @(
        ssh -i $keyPath `
            -o ConnectTimeout=10 `
            -o StrictHostKeyChecking=no `
            "ec2-user@$ip" `
            "sudo cat /root/sienna-central-credentials.txt"
    ) -join "`n"

    if ($LASTEXITCODE -ne 0) {
        throw "SSH failed while reading the Elasticsearch credentials."
    }

    if ($credentials -notmatch "(?s)Elastic user:.*?Password:\s*([^\s\r\n]+)") {
        throw "Could not parse the Elasticsearch password from the remote credentials file."
    }
    $elasticPassword = $Matches[1]

    $requestBody = @{ ids = @($keyId) } | ConvertTo-Json -Compress
    $requestBodyBase64 = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes($requestBody)
    )

    Write-Host "Revoking Elasticsearch API key $keyId..."
    $revokeResponseText = @(
        ssh -i $keyPath `
            -o ConnectTimeout=10 `
            -o StrictHostKeyChecking=no `
            "ec2-user@$ip" `
            "echo $requestBodyBase64 | base64 -d | curl -sS -X DELETE -u 'elastic:$elasticPassword' -H 'Content-Type: application/json' --data-binary '@-' http://localhost:9200/_security/api_key"
    ) -join "`n"

    if ($LASTEXITCODE -ne 0) {
        throw "SSH failed while revoking the Elasticsearch API key."
    }

    $revokeResponse = $revokeResponseText | ConvertFrom-Json
    if ($revokeResponse.error_count -ne 0 -or
        $revokeResponse.invalidated_api_keys -notcontains $keyId) {
        throw "Elasticsearch did not confirm revocation of API key $keyId. Response: $revokeResponseText"
    }

    $verificationResponseText = @(
        ssh -i $keyPath `
            -o ConnectTimeout=10 `
            -o StrictHostKeyChecking=no `
            "ec2-user@$ip" `
            "curl -sS -u 'elastic:$elasticPassword' --get --data-urlencode 'id=$keyId' http://localhost:9200/_security/api_key"
    ) -join "`n"
    $verificationResponse = $verificationResponseText | ConvertFrom-Json
    $remoteKey = @($verificationResponse.api_keys) |
        Where-Object { $_.id -eq $keyId } |
        Select-Object -First 1

    if (-not $remoteKey -or -not $remoteKey.invalidated) {
        throw "Elasticsearch did not report API key $keyId as invalidated."
    }

    Write-Host "Removing the already-revoked API key from Terraform state..."
    Invoke-Terraform -Arguments @(
        "state", "rm",
        "elasticstack_elasticsearch_security_api_key.github_dac_key"
    )

    $destroyArguments = @(
        "destroy",
        "-target=github_actions_secret.kibana_api_key"
    )
    if ($AutoApprove) {
        $destroyArguments += "-auto-approve"
    }
    Write-Host "Destroying the GitHub Actions secret..."
    Invoke-Terraform -Arguments $destroyArguments

    $destroyArguments = @("destroy")
    if ($AutoApprove) {
        $destroyArguments += "-auto-approve"
    }
    Write-Host "Destroying the remaining infrastructure..."
    Invoke-Terraform -Arguments $destroyArguments
}
finally {
    Pop-Location
}
