$file = "$env:TEMP\CloudRedirectCLI.exe"
Invoke-WebRequest "https://github.com/Selectively11/CloudRedirect/releases/latest/download/CloudRedirectCLI.exe" -OutFile $file
Start-Process $file "/stfixer" -Wait
