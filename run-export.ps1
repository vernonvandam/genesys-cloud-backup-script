#Requires -Version 5.1

<#
.SYNOPSIS
    Exports Genesys Cloud configuration using Terraform, including Architect
    flows as YAML, then archives the completed export into an immutable,
    timestamped backup.

.DESCRIPTION
    Terraform is responsible for exporting Genesys Cloud configuration and
    Architect flows. Architect YAML export is enabled by setting
    use_legacy_architect_flow_exporter = false in the Terraform export
    configuration.

    The script:
      1. Validates required Terraform files, executable and directories.
      2. Cleans the working Terraform export directory.
      3. Runs Terraform initialisation and export.
      4. Validates the Terraform export, including generated YAML files.
      5. Creates an immutable timestamped backup.
      6. Validates the backup and writes export metadata.

.NOTES
    Existing backups are never modified or deleted.
    The working Terraform export directory is cleaned before every run.
    Archy is not required; Terraform exports Architect flows directly.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$TerraformDirectory = Join-Path $ProjectRoot "terraform"
$TerraformExportDirectory = Join-Path $TerraformDirectory "export"
$TerraformExe = Join-Path $ProjectRoot "tools\terraform\terraform.exe"
$BackupsDirectory = Join-Path $ProjectRoot "backups"

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

function Write-Step {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
}

function Write-Success {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-WarningMessage {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Info {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[INFO] $Message" -ForegroundColor Gray
}

function Write-Failure {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host "[FAILED] $Message" -ForegroundColor Red
}

# ---------------------------------------------------------------------------
# Utility functions
# ---------------------------------------------------------------------------

function Test-RequiredFile {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description was not found: $Path"
    }

    Write-Success "$Description found."
}

function Test-RequiredDirectory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Description was not found: $Path"
    }

    Write-Success "$Description found."
}

function Remove-WorkingDirectory {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (Test-Path -LiteralPath $Path) {
        Write-Info "Removing existing $Description..."
        Remove-Item -LiteralPath $Path -Recurse -Force
    }

    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Write-Success "$Description prepared."
}

# ---------------------------------------------------------------------------
# Export validation
# ---------------------------------------------------------------------------

function Get-ExportFiles {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "$Description directory was not created: $Path"
    }

    $Files = @(
        Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction Stop
    )

    if ($Files.Count -eq 0) {
        throw "$Description directory is empty: $Path"
    }

    Write-Success "$Description contains $($Files.Count) file(s)."
    return $Files
}


function Get-FileHashManifest {
    param (
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [array]$Files
    )

    $ResolvedRoot = (Resolve-Path -LiteralPath $RootPath).Path.TrimEnd([char[]]@('\', '/'))
    $Manifest = @(
        foreach ($File in $Files) {
            $FullPath = (Resolve-Path -LiteralPath $File.FullName).Path
            $RelativePath = $FullPath.Substring($ResolvedRoot.Length).TrimStart([char[]]@('\', '/'))
            $Hash = Get-FileHash -LiteralPath $FullPath -Algorithm SHA256 -ErrorAction Stop

            [PSCustomObject]@{
                RelativePath = $RelativePath.Replace('\', '/')
                SHA256       = $Hash.Hash
                Length       = [long]$File.Length
            }
        }
    )

    return $Manifest
}

function Compare-FileHashManifests {
    param (
        [Parameter(Mandatory = $true)]
        [array]$SourceManifest,

        [Parameter(Mandatory = $true)]
        [array]$BackupManifest
    )

    $SourceByPath = @{}
    foreach ($Entry in $SourceManifest) {
        $SourceByPath[$Entry.RelativePath] = $Entry
    }

    $BackupByPath = @{}
    foreach ($Entry in $BackupManifest) {
        $BackupByPath[$Entry.RelativePath] = $Entry
    }

    $Errors = @()

    foreach ($RelativePath in $SourceByPath.Keys) {
        if (-not $BackupByPath.ContainsKey($RelativePath)) {
            $Errors += "Missing from backup: $RelativePath"
            continue
        }

        if ($SourceByPath[$RelativePath].SHA256 -ne $BackupByPath[$RelativePath].SHA256) {
            $Errors += "SHA-256 mismatch: $RelativePath"
        }

        if ($SourceByPath[$RelativePath].Length -ne $BackupByPath[$RelativePath].Length) {
            $Errors += "File size mismatch: $RelativePath"
        }
    }

    foreach ($RelativePath in $BackupByPath.Keys) {
        if (-not $SourceByPath.ContainsKey($RelativePath)) {
            $Errors += "Unexpected file in backup: $RelativePath"
        }
    }

    if ($Errors.Count -gt 0) {
        throw "Backup content verification failed:`n - $($Errors -join "`n - ")"
    }

    Write-Success "SHA-256 verification passed for $($SourceManifest.Count) file(s)."
}

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------

function Write-ExportMetadata {
    param (
        [Parameter(Mandatory = $true)]
        [string]$BackupDirectory,

        [Parameter(Mandatory = $true)]
        [datetime]$StartTime,

        [Parameter(Mandatory = $true)]
        [datetime]$EndTime,

        [Parameter(Mandatory = $true)]
        [array]$ExportFiles,

        [Parameter(Mandatory = $true)]
        [array]$FileManifest
    )

    $MetadataPath = Join-Path $BackupDirectory "export-metadata.json"
    $YamlFiles = @($ExportFiles | Where-Object { $_.Extension -ieq ".yaml" -or $_.Extension -ieq ".yml" })

    $Metadata = [PSCustomObject]@{
        ExportTimestamp = $EndTime.ToString("o")
        StartTime       = $StartTime.ToString("o")
        EndTime         = $EndTime.ToString("o")
        DurationSeconds = [math]::Round(($EndTime - $StartTime).TotalSeconds, 2)
        ExportEngine    = "Terraform"
        Terraform       = [PSCustomObject]@{
            ExportFileCount    = $ExportFiles.Count
            ArchitectYamlCount = $YamlFiles.Count
        }
        Integrity        = [PSCustomObject]@{
            Algorithm       = "SHA256"
            Verification    = "Passed"
            VerifiedFileCount = $FileManifest.Count
        }
        Files = @(
            foreach ($Entry in $FileManifest) {
                [PSCustomObject]@{
                    Path   = $Entry.RelativePath
                    SHA256 = $Entry.SHA256
                    SizeBytes = $Entry.Length
                }
            }
        )
    }

    $Metadata |
        ConvertTo-Json -Depth 10 |
        Set-Content -LiteralPath $MetadataPath -Encoding UTF8

    Write-Success "Export metadata written."
}

# ---------------------------------------------------------------------------
# Main export process
# ---------------------------------------------------------------------------

$StartTime = Get-Date

try {
    Write-Host ""
    Write-Host "Genesys Cloud Customer Export" -ForegroundColor White
    Write-Host "Project: $ProjectRoot" -ForegroundColor Gray
    Write-Host ""

    # -----------------------------------------------------------------------
    # 1. Validate prerequisites
    # -----------------------------------------------------------------------

    Write-Step "1/6 Validating prerequisites"

    Test-RequiredFile -Path $TerraformExe -Description "Terraform executable"
    Test-RequiredDirectory -Path $TerraformDirectory -Description "Terraform directory"

    if (-not (Test-Path -LiteralPath $BackupsDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $BackupsDirectory -Force | Out-Null
    }

    Write-Success "All prerequisites validated."

    # -----------------------------------------------------------------------
    # 2. Clean working Terraform export directory
    # -----------------------------------------------------------------------

    Write-Step "2/6 Preparing Terraform export directory"

    Remove-WorkingDirectory `
        -Path $TerraformExportDirectory `
        -Description "Terraform export directory"

    # -----------------------------------------------------------------------
    # 3. Run Terraform export
    # -----------------------------------------------------------------------

    Write-Step "3/6 Running Terraform export"

    Push-Location $TerraformDirectory
    try {
        & $TerraformExe init
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform init failed with exit code $LASTEXITCODE."
        }
        Write-Success "Terraform initialized."

        & $TerraformExe apply -auto-approve
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform export failed with exit code $LASTEXITCODE."
        }
        Write-Success "Terraform export completed."
    }
    finally {
        Pop-Location
    }

    # -----------------------------------------------------------------------
    # 4. Validate Terraform export
    # -----------------------------------------------------------------------

    Write-Step "4/6 Validating Terraform export"

    $ExportFiles = @(Get-ExportFiles `
        -Path $TerraformExportDirectory `
        -Description "Terraform export")

    $YamlFiles = @($ExportFiles | Where-Object { $_.Extension -ieq ".yaml" -or $_.Extension -ieq ".yml" })
    Write-Info "Architect YAML files found: $($YamlFiles.Count)"
    Write-Success "Terraform export validation completed."

    # -----------------------------------------------------------------------
    # 5. Create immutable timestamped backup
    # -----------------------------------------------------------------------

    Write-Step "5/6 Creating timestamped backup"

    $EndTime = Get-Date
    $BackupTimestamp = $EndTime.ToString("yyyyMMdd-HHmmss")
    $BackupDirectory = Join-Path $BackupsDirectory $BackupTimestamp

    if (Test-Path -LiteralPath $BackupDirectory) {
        throw "Backup directory already exists. The existing backup will not be overwritten: $BackupDirectory"
    }

    New-Item -ItemType Directory -Path $BackupDirectory -Force | Out-Null

    # Copy the contents of the Terraform export directly into the timestamped
    # backup directory. This avoids an unnecessary terraform\export hierarchy.
    Get-ChildItem -LiteralPath $TerraformExportDirectory -Force |
        Copy-Item -Destination $BackupDirectory -Recurse -Force

    Write-Success "Backup created: $BackupDirectory"

    # -----------------------------------------------------------------------
    # 6. Validate backup and write metadata
    # -----------------------------------------------------------------------

    Write-Step "6/6 Validating backup"

    # Export files are stored directly in the timestamped backup directory.
    # Metadata is written only after file verification, so it is not included
    # in the source-export-versus-backup manifest comparison.
    $BackupExportDirectory = $BackupDirectory
    $BackupFiles = @(Get-ExportFiles `
        -Path $BackupExportDirectory `
        -Description "Backed-up Terraform export")

    if ($BackupFiles.Count -ne $ExportFiles.Count) {
        throw "Backup validation failed: source has $($ExportFiles.Count) file(s), but backup has $($BackupFiles.Count) file(s)."
    }

    $BackupYamlFiles = @($BackupFiles | Where-Object { $_.Extension -ieq ".yaml" -or $_.Extension -ieq ".yml" })
    if ($BackupYamlFiles.Count -ne $YamlFiles.Count) {
        throw "Backup validation failed: source has $($YamlFiles.Count) YAML file(s), but backup has $($BackupYamlFiles.Count) YAML file(s)."
    }

    Write-Info "Calculating SHA-256 hashes for source export files..."
    $SourceManifest = @(
        Get-FileHashManifest `
            -RootPath $TerraformExportDirectory `
            -Files $ExportFiles
    )

    Write-Info "Calculating SHA-256 hashes for backup files..."
    $BackupManifest = @(
        Get-FileHashManifest `
            -RootPath $BackupExportDirectory `
            -Files $BackupFiles
    )

    Compare-FileHashManifests `
        -SourceManifest $SourceManifest `
        -BackupManifest $BackupManifest

    Write-ExportMetadata `
        -BackupDirectory $BackupDirectory `
        -StartTime $StartTime `
        -EndTime (Get-Date) `
        -ExportFiles $ExportFiles `
        -FileManifest $SourceManifest

    Write-Success "Backup validation completed."

    # -----------------------------------------------------------------------
    # Completion
    # -----------------------------------------------------------------------

    $CompletionTime = Get-Date

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host "EXPORT COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "================================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "Backup:"
    Write-Host "  $BackupDirectory"
    Write-Host ""
    Write-Host "Terraform export files:"
    Write-Host "  $($ExportFiles.Count)"
    Write-Host "Architect YAML files:"
    Write-Host "  $($YamlFiles.Count)"
    Write-Host "Duration:"
    Write-Host "  $([math]::Round(($CompletionTime - $StartTime).TotalSeconds, 2)) seconds"
    Write-Host ""
}
catch {
    Write-Host ""
    Write-Failure "EXPORT FAILED"
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""
    Write-Host "Existing backups have not been modified." -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
