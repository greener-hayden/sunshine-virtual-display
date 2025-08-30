param(
    [Parameter(Mandatory)][ValidateSet('install','uninstall')]
    [string]$Action
)

$logDir = Join-Path $PSScriptRoot 'logs'
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $logDir "portable-$Action-$timestamp.log"
Start-Transcript -Path $logPath -Append | Out-Null

try {
    switch ($Action) {
        'install' {
            Write-Output 'Performing portable install...'
            # TODO: Add install logic
        }
        'uninstall' {
            Write-Output 'Performing portable uninstall...'
            # TODO: Add uninstall logic
        }
    }
}
finally {
    Stop-Transcript | Out-Null
}
