$ErrorActionPreference = 'Stop'

$installer = Join-Path $PSScriptRoot '../scripts/install-fatou.ps1'
$testDir = Join-Path ([System.IO.Path]::GetTempPath()) ("fatou-test-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testDir | Out-Null

# Replace network clients so failures are deterministic and require no token.
function Invoke-WebRequest {
    param($uri, $outFile)
    $kind = if ($uri.EndsWith('.sha256')) { 'checksum' } else { 'archive' }
    $testCase["${kind}Attempts"]++
    if ($testCase["${kind}Attempts"] -le $testCase["${kind}Failures"]) {
        Set-Content -Path $outFile -Value 'partial download'
        throw 'Connection reset by peer'
    }
    if ($kind -eq 'archive') {
        Copy-Item -Path (Join-Path $testDir 'archive.zip') -Destination $outFile -Force
    } elseif ($testCase.badChecksum) {
        Set-Content -Path $outFile -Value 'incorrect-checksum'
    } else {
        Set-Content -Path $outFile -Value $checksum
    }
}

function gh {
    $global:LASTEXITCODE = 0
    if ($testCase.badProvenance) {
        $global:LASTEXITCODE = 1
        'attestation signature verification failed'
    }
}

function Start-Sleep {
    param($seconds)
}

try {
    $binary = Join-Path $testDir 'fatou.exe'
    Set-Content -Path $binary -Value 'test binary'
    Compress-Archive -Path $binary -DestinationPath (Join-Path $testDir 'archive.zip')
    $checksum = (Get-FileHash -Path (Join-Path $testDir 'archive.zip') -Algorithm SHA256).Hash
    $env:FATOU_INSTALL_DIR = Join-Path $testDir 'install'
    $env:FATOU_VERSION = 'v0.0.0'
    $env:FATOU_VERIFY_CHECKSUM = 'true'

    $cases = @(
        @{
            name = 'successful download'
            archiveFailures = 0
            checksumFailures = 0
            success = $true
            archive = 1
            checksum = 1
            message = 'Checksum verified.'
        },
        @{
            name = 'interrupted archive recovers on the last attempt'
            archiveFailures = 3
            checksumFailures = 0
            success = $true
            archive = 4
            checksum = 1
            message = 'Checksum verified.'
        },
        @{
            name = 'archive retries are bounded'
            archiveFailures = 10
            checksumFailures = 0
            success = $false
            archive = 4
            checksum = 0
            message = 'Connection reset by peer'
        },
        @{
            name = 'interrupted checksum recovers on the last attempt'
            archiveFailures = 0
            checksumFailures = 3
            success = $true
            archive = 1
            checksum = 4
            message = 'Checksum verified.'
        },
        @{
            name = 'unavailable checksum still warns and continues'
            archiveFailures = 0
            checksumFailures = 10
            success = $true
            archive = 1
            checksum = 4
            message = 'skipping verification.'
        },
        @{
            name = 'checksum mismatch aborts after a retry'
            archiveFailures = 1
            checksumFailures = 0
            badChecksum = $true
            success = $false
            archive = 2
            checksum = 1
            message = 'Checksum mismatch'
        },
        @{
            name = 'invalid provenance aborts after a retry'
            archiveFailures = 1
            checksumFailures = 0
            badProvenance = $true
            success = $false
            archive = 2
            checksum = 1
            message = 'Provenance verification failed'
        }
    )
    $failures = 0
    foreach ($case in $cases) {
        $testCase = $case.Clone()
        $testCase.archiveAttempts = 0
        $testCase.checksumAttempts = 0
        Remove-Item -Recurse -Force $env:FATOU_INSTALL_DIR -ErrorAction SilentlyContinue
        $succeeded = $true
        try {
            & $installer *> (Join-Path $testDir 'output')
        } catch {
            $_ | Out-String | Add-Content -Path (Join-Path $testDir 'output')
            $succeeded = $false
        }
        $installed = Join-Path $env:FATOU_INSTALL_DIR 'fatou.exe'
        $passed = ($succeeded -eq $case.success) -and
            ($testCase.archiveAttempts -eq $case.archive) -and
            ($testCase.checksumAttempts -eq $case.checksum) -and
            (Get-Content -Raw (Join-Path $testDir 'output')).Contains($case.message)
        if ($case.success) {
            $passed = $passed -and (Test-Path $installed)
            if ($passed) {
                $passed = (Get-Content -Raw $installed) -eq (Get-Content -Raw $binary)
            }
        } else {
            $passed = $passed -and -not (Test-Path $installed)
        }
        if ($passed) {
            Write-Host "PASS: $($case.name)"
        } else {
            Write-Host "FAIL: $($case.name) (archive attempts $($testCase.archiveAttempts), checksum attempts $($testCase.checksumAttempts))"
            Get-Content -Path (Join-Path $testDir 'output')
            $failures++
        }
    }
    if ($failures -gt 0) { exit 1 }
    exit 0
} finally {
    Remove-Item -Recurse -Force $testDir
}
