Param()

$ErrorActionPreference = 'Stop'

$repo = if ($env:FATOU_REPO) { $env:FATOU_REPO } else { 'jolars/fatou' }
$version = if ($env:FATOU_VERSION) { $env:FATOU_VERSION } else { 'latest' }
$installDir = if ($env:FATOU_INSTALL_DIR) { $env:FATOU_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA 'Programs\fatou\bin' }
$verify = if ($env:FATOU_VERIFY_CHECKSUM) { $env:FATOU_VERIFY_CHECKSUM } else { 'true' }

$arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
switch ($arch) {
    'X64' { $target = 'x86_64-pc-windows-msvc' }
    'Arm64' { $target = 'aarch64-pc-windows-msvc' }
    default { throw "Unsupported Windows architecture: $arch" }
}

$asset = "fatou-$target.zip"

if ($version -eq 'latest') {
    $base = "https://github.com/$repo/releases/latest/download"
} else {
    $tag = if ($version.StartsWith('v')) { $version } else { "v$version" }
    $base = "https://github.com/$repo/releases/download/$tag"
}
$url = "$base/$asset"

$tmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("fatou-install-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmpDir | Out-Null

try {
    $zipPath = Join-Path $tmpDir $asset
    Write-Host "Downloading $asset ($version)..."
    Invoke-WebRequest -Uri $url -OutFile $zipPath

    if ($verify -eq 'true') {
        # Fetch the published checksum sidecar. Older releases may not have one,
        # in which case we warn and continue rather than fail.
        $shaPath = "$zipPath.sha256"
        $haveChecksum = $true
        try {
            Invoke-WebRequest -Uri "$url.sha256" -OutFile $shaPath
        } catch {
            $haveChecksum = $false
            Write-Warning "No published checksum for $asset; skipping verification."
        }
        if ($haveChecksum) {
            $expected = ((Get-Content -Raw $shaPath).Trim() -split '\s+')[0].ToLower()
            $actual = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
            if ($expected -ne $actual) {
                throw "Checksum mismatch for ${asset}: expected $expected, actual $actual"
            }
            Write-Host "Checksum verified."
        }
    }

    # Verify build provenance when the gh CLI is available. Stronger than the
    # checksum: it ties the archive to the workflow that built it. A present-
    # but-failing attestation aborts; a missing attestation (older releases) or
    # missing gh warns and continues. When no attestation exists, gh reports it
    # either as "no attestations found" or as an HTTP 404 on the attestations
    # API endpoint, so tolerate both.
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        $attestOut = & gh attestation verify $zipPath --repo $repo 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Verified $asset provenance (attestation)"
        } elseif ($attestOut -match '(?i)no attestation|http 404') {
            Write-Warning "No provenance attestation for this release; skipping"
            # gh left a non-zero $LASTEXITCODE; clear it so the step, whose exit
            # code GitHub derives from $LASTEXITCODE, does not inherit it.
            $global:LASTEXITCODE = 0
        } else {
            Write-Host $attestOut
            throw "Provenance verification failed for $asset"
        }
    } else {
        Write-Warning "gh CLI not found; skipping provenance verification"
    }

    Expand-Archive -Path $zipPath -DestinationPath $tmpDir -Force
    New-Item -ItemType Directory -Path $installDir -Force | Out-Null
    Copy-Item -Path (Join-Path $tmpDir 'fatou.exe') -Destination (Join-Path $installDir 'fatou.exe') -Force

    Write-Host "Installed fatou to $(Join-Path $installDir 'fatou.exe')"
}
finally {
    Remove-Item -Recurse -Force $tmpDir -ErrorAction SilentlyContinue
}
