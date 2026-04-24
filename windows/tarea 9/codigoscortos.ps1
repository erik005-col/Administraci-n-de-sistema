$msi = Get-ChildItem -Path C:\MFA_Setup -Filter "*.msi" -Recurse | Select-Object -First 1
Start-Process -FilePath "msiexec.exe" -ArgumentList "/i `"$($msi.FullName)`""
