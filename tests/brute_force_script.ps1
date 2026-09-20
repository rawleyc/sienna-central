1..20 | ForEach-Object {
     $cred = New-Object System.Management.Automation.PSCredential(
         $user,
         (ConvertTo-SecureString $badPassword -AsPlainText -Force)
     )

     try {
         Start-Process powershell.exe -Credential $cred -ArgumentList '-NoProfile -Command "exit"' -ErrorAction Stop
     }
     catch {
         Write-Host "Attempt $_ failed as expected."
     }

     Start-Sleep -Seconds 1
 }