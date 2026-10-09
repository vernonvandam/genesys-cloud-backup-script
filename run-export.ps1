##Requires -Version 5.1

<#
.SYNOPSIS
    Exports Genesys Cloud configuration using Terraform and Architect flows using Archy,
    then archives the completed exports into an immutable timestamped backup.

.DESCRIPTION
    Terraform is the source of truth for the Architect flows to be exported.

    The script:
      1. Validates required executables, configuration and directories.
      2. Cleans the working Terraform and Archy export directories.
      3. Runs Terraform export.
      4. Reads the exported genesyscloud_flow.tf.json.
      5. Determines the Architect flows and their types from Terraform.
      6. Exports each supported Architect flow using Archy.
      7. Validates both export locations.
      8. Creates an immutable timestamped backup.
      9. Writes metadata describing the export.

.NOTES
    Existing backups are never modified or deleted.
    Working export directories are cleaned before every run.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

$TerraformDirectory = Join-Path $ProjectRoot "terraform"
$TerraformExportDirectory = Join-Path $TerraformDirectory "export"

$ArchyDirectory = Join-Path $ProjectRoot "archy"
$ArchyExportDirectory = Join-Path $ArchyDirectory "export"
$ArchyConfigDirectory = Join-Path $ArchyDirectory "config"
$ArchyConfig = Join-Path $ArchyConfigDirectory "options.yaml"

$TerraformExe = Join-Path $ProjectRoot "tools\terraform\terraform.exe"
$ArchyExe = Join-Path $ProjectRoot "tools\archy\archy.exe"

$BackupsDirectory = Join-Path $ProjectRoot "backups"

$TerraformFlowJson = Join-Path `
    $TerraformExportDirectory `
    "flow\genesyscloud_flow.tf.json"


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Architect flow types that Archy should process.
#
# Terraform may export many different genesyscloud_flow resource types.
# Not every flow/resource type is necessarily an Architect flow that Archy
# can export.
#
# Add additional types here when they are confirmed to be supported by Archy.
$ArchySupportedFlowTypes = @(
    "inboundcall",
    "inqueuecall",
    "outboundcall",
    "securecall",
    "voicemail",
    "emailsend",
    "businessprocess",
    "inboundchat",
    "inboundemail",
    "inboundshortmessage",
    "inqueueemail",
    "inqueueshortmessage",
    "surveyinvite",
    "workflow",
    "workitem",
    "bot",
    "digitalbot",
    "voice",
    "voicesurvey",
    "commonmodule"
)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

function Write-Step {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Host ""
    Write-Host "================================================================" `
        -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "================================================================" `
        -ForegroundColor Cyan
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
# Terraform flow discovery
# ---------------------------------------------------------------------------

function Get-ArchyFlowsFromTerraformExport {
    param (
        [Parameter(Mandatory = $true)]
        [string]$TerraformFlowJsonPath
    )

    if (-not (Test-Path -LiteralPath $TerraformFlowJsonPath -PathType Leaf)) {
        throw "Terraform flow export JSON was not found: $TerraformFlowJsonPath"
    }

    Write-Info "Reading Terraform flow export:"
    Write-Info $TerraformFlowJsonPath

    try {
        $TerraformFlowJson = Get-Content `
            -LiteralPath $TerraformFlowJsonPath `
            -Raw `
            -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        throw "Unable to parse Terraform flow export JSON '$TerraformFlowJsonPath'. $($_.Exception.Message)"
    }

    if ($null -eq $TerraformFlowJson.resource) {
        throw "The Terraform flow export does not contain a 'resource' section."
    }

    if ($null -eq $TerraformFlowJson.resource.genesyscloud_flow) {
        throw "The Terraform flow export does not contain any 'genesyscloud_flow' resources."
    }

    $FlowResources = $TerraformFlowJson.resource.genesyscloud_flow

    $Flows = @()

    foreach ($Resource in $FlowResources.PSObject.Properties) {

        $ResourceName = $Resource.Name
        $Flow = $Resource.Value

        if ($null -eq $Flow) {
            Write-WarningMessage `
                "Skipping Terraform flow resource '$ResourceName' because it contains no value."

            continue
        }

        if ([string]::IsNullOrWhiteSpace([string]$Flow.name)) {
            Write-WarningMessage `
                "Skipping Terraform flow resource '$ResourceName' because it has no name."

            continue
        }

        if ([string]::IsNullOrWhiteSpace([string]$Flow.type)) {
            Write-WarningMessage `
                "Skipping Terraform flow '$($Flow.name)' because it has no type."

            continue
        }

        $FlowType = ([string]$Flow.type).ToLowerInvariant()

        $Flows += [PSCustomObject]@{
            ResourceName = $ResourceName
            Name         = [string]$Flow.name
            Type         = $FlowType
        }
    }

    if ($Flows.Count -eq 0) {
        throw "No valid genesyscloud_flow resources were found in '$TerraformFlowJsonPath'."
    }

    return $Flows
}


function Get-ArchyExportableFlows {
    param (
        [Parameter(Mandatory = $true)]
        [array]$Flows
    )

    $ExportableFlows = @()
    $SkippedFlows = @()

    foreach ($Flow in $Flows) {

        if ($ArchySupportedFlowTypes -contains $Flow.Type) {
            $ExportableFlows += $Flow
        }
        else {
            $SkippedFlows += $Flow
        }
    }

    return [PSCustomObject]@{
        Exportable = $ExportableFlows
        Skipped    = $SkippedFlows
    }
}


# ---------------------------------------------------------------------------
# Export validation
# ---------------------------------------------------------------------------

function Test-ExportDirectory {
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
        Get-ChildItem `
            -LiteralPath $Path `
            -Recurse `
            -File `
            -ErrorAction Stop
    )

    if ($Files.Count -eq 0) {
        throw "$Description directory is empty: $Path"
    }

    Write-Success "$Description contains $($Files.Count) file(s)."
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
        [array]$TerraformFlows,

        [Parameter(Mandatory = $true)]
        [array]$ExportedFlows,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array]$SkippedFlows
    )

    $MetadataPath = Join-Path $BackupDirectory "export-metadata.json"

    $Metadata = [PSCustomObject]@{
        ExportTimestamp = $EndTime.ToString("o")
        StartTime       = $StartTime.ToString("o")
        EndTime         = $EndTime.ToString("o")
        DurationSeconds = [math]::Round(
            ($EndTime - $StartTime).TotalSeconds,
            2
        )

        Terraform = [PSCustomObject]@{
            FlowResourceCount = $TerraformFlows.Count
        }

        Archy = [PSCustomObject]@{
            ExportedFlowCount = $ExportedFlows.Count
            SkippedFlowCount  = $SkippedFlows.Count
            SupportedTypes    = @($ArchySupportedFlowTypes)
        }

        ExportedFlows = @(
            foreach ($Flow in $ExportedFlows) {
                [PSCustomObject]@{
                    ResourceName = $Flow.ResourceName
                    Name         = $Flow.Name
                    Type         = $Flow.Type
                }
            }
        )

        SkippedFlows = @(
            foreach ($Flow in $SkippedFlows) {
                [PSCustomObject]@{
                    ResourceName = $Flow.ResourceName
                    Name         = $Flow.Name
                    Type         = $Flow.Type
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

    Write-Step "1/8 Validating prerequisites"

    Test-RequiredFile `
        -Path $TerraformExe `
        -Description "Terraform executable"

    Test-RequiredFile `
        -Path $ArchyExe `
        -Description "Archy executable"

    Test-RequiredFile `
        -Path $ArchyConfig `
        -Description "Archy configuration"

    Test-RequiredDirectory `
        -Path $TerraformDirectory `
        -Description "Terraform directory"

    Test-RequiredDirectory `
        -Path $ArchyDirectory `
        -Description "Archy directory"

    if (-not (Test-Path -LiteralPath $BackupsDirectory)) {
        New-Item `
            -ItemType Directory `
            -Path $BackupsDirectory `
            -Force |
            Out-Null
    }

    Write-Success "All prerequisites validated."


    # -----------------------------------------------------------------------
    # 2. Clean working export directories
    # -----------------------------------------------------------------------

    Write-Step "2/8 Preparing working export directories"

    Remove-WorkingDirectory `
        -Path $TerraformExportDirectory `
        -Description "Terraform export directory"

    Remove-WorkingDirectory `
        -Path $ArchyExportDirectory `
        -Description "Archy export directory"


    # -----------------------------------------------------------------------
    # 3. Terraform export
    # -----------------------------------------------------------------------

    Write-Step "3/8 Running Terraform export"

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
    # 4. Discover Architect flows from Terraform export
    # -----------------------------------------------------------------------

    Write-Step "4/8 Discovering Architect flows from Terraform export"

    if (-not (Test-Path `
        -LiteralPath $TerraformFlowJson `
        -PathType Leaf)) {

        throw "Terraform flow export was not generated: $TerraformFlowJson"
    }

    $TerraformFlows = @(
        Get-ArchyFlowsFromTerraformExport `
            -TerraformFlowJsonPath $TerraformFlowJson
    )

    Write-Success `
        "Found $($TerraformFlows.Count) flow resource(s) in Terraform export."

    $FlowClassification = Get-ArchyExportableFlows `
        -Flows $TerraformFlows

    $ExportableFlows = @($FlowClassification.Exportable)
    $SkippedFlows = @($FlowClassification.Skipped)

    Write-Host ""
    Write-Host "Terraform flow discovery summary:" `
        -ForegroundColor White

    Write-Host "  Total resources : $($TerraformFlows.Count)"
    Write-Host "  Archy exports   : $($ExportableFlows.Count)"
    Write-Host "  Skipped         : $($SkippedFlows.Count)"

    if ($SkippedFlows.Count -gt 0) {

        Write-Host ""
        Write-WarningMessage "The following Terraform flow resources are not configured for Archy export:"

        foreach ($Flow in $SkippedFlows) {
            Write-Host "  - $($Flow.Name) [$($Flow.Type)]"
        }
    }


    # -----------------------------------------------------------------------
    # 5. Archy flow export
    # -----------------------------------------------------------------------

    Write-Step "5/8 Exporting Architect flows with Archy"

    if ($ExportableFlows.Count -eq 0) {

        Write-WarningMessage `
            "No Terraform flows match the configured Archy-supported flow types."

    }
    else {

        $ExportedFlows = @()

        foreach ($Flow in $ExportableFlows) {

            Write-Host ""
            Write-Host "Exporting flow:" -ForegroundColor Yellow
            Write-Host "  Resource : $($Flow.ResourceName)"
            Write-Host "  Name     : $($Flow.Name)"
            Write-Host "  Type     : $($Flow.Type)"
            Write-Host ""

            & $ArchyExe export `
                --flowName $Flow.Name `
                --flowType $Flow.Type `
                --optionsFile $ArchyConfig `
                --exportType yaml `
                --outputDir $ArchyExportDirectory `
                --debug `
                --force

            if ($LASTEXITCODE -ne 0) {
                throw `
                    "Archy export failed for flow '$($Flow.Name)' " +
                    "($($Flow.Type)) with exit code $LASTEXITCODE."
            }

            # Prefix the Archy-generated YAML filename with the flow type.
            $ArchyYamlFiles = Get-ChildItem -Path $ArchyExportDirectory -Filter "*.yaml" -File

            foreach ($YamlFile in $ArchyYamlFiles) {
                if ($YamlFile.BaseName -like "$($Flow.Name)*") {
                    $NewName = "{0}_{1}{2}" -f $Flow.Type, $YamlFile.BaseName, $YamlFile.Extension
                    Rename-Item -LiteralPath $YamlFile.FullName -NewName $NewName
                    break
                }
            }

            $ExportedFlows += $Flow
            Write-Success "Exported: $($Flow.Name)"

        }
    }


    # -----------------------------------------------------------------------
    # 6. Validate exports
    # -----------------------------------------------------------------------

    Write-Step "6/8 Validating generated exports"

    Test-ExportDirectory `
        -Path $TerraformExportDirectory `
        -Description "Terraform export"

    if ($ExportableFlows.Count -gt 0) {

        Test-ExportDirectory `
            -Path $ArchyExportDirectory `
            -Description "Archy export"
    }
    else {

        Write-Info `
            "No Archy export validation required because no supported flows were found."
    }

    Write-Success "Export validation completed."


    # -----------------------------------------------------------------------
    # 7. Create immutable backup
    # -----------------------------------------------------------------------

    Write-Step "7/8 Creating timestamped backup"

    $EndTime = Get-Date

    $BackupTimestamp = $EndTime.ToString("yyyyMMdd-HHmmss")

    $BackupDirectory = Join-Path `
        $BackupsDirectory `
        $BackupTimestamp

    if (Test-Path -LiteralPath $BackupDirectory) {
        throw `
            "Backup directory already exists. " +
            "The existing backup will not be overwritten: $BackupDirectory"
    }

    New-Item `
        -ItemType Directory `
        -Path $BackupDirectory `
        -Force |
        Out-Null

    $BackupTerraformDirectory = Join-Path `
        $BackupDirectory `
        "terraform"

    $BackupArchyDirectory = Join-Path `
        $BackupDirectory `
        "archy"

    New-Item `
        -ItemType Directory `
        -Path $BackupTerraformDirectory `
        -Force |
        Out-Null

    New-Item `
        -ItemType Directory `
        -Path $BackupArchyDirectory `
        -Force |
        Out-Null

    # Copy Terraform export
    Copy-Item `
        -LiteralPath $TerraformExportDirectory `
        -Destination $BackupTerraformDirectory `
        -Recurse `
        -Force

    # Copy Archy export when one exists
    if ($ExportableFlows.Count -gt 0) {

        Copy-Item `
            -LiteralPath $ArchyExportDirectory `
            -Destination $BackupArchyDirectory `
            -Recurse `
            -Force
    }

    Write-Success "Backup created: $BackupDirectory"


    # -----------------------------------------------------------------------
    # 8. Validate backup and write metadata
    # -----------------------------------------------------------------------

    Write-Step "8/8 Validating backup"

    $BackupTerraformExport = Join-Path `
        $BackupDirectory `
        "terraform\export"

    if (-not (Test-Path `
        -LiteralPath $BackupTerraformExport `
        -PathType Container)) {

        throw `
            "Terraform export was not copied correctly to backup: " +
            "$BackupTerraformExport"
    }

    if ($ExportableFlows.Count -gt 0) {

        $BackupArchyExport = Join-Path `
            $BackupDirectory `
            "archy\export"

        if (-not (Test-Path `
            -LiteralPath $BackupArchyExport `
            -PathType Container)) {

            throw `
                "Archy export was not copied correctly to backup: " +
                "$BackupArchyExport"
        }
    }

    Write-ExportMetadata `
        -BackupDirectory $BackupDirectory `
        -StartTime $StartTime `
        -EndTime $EndTime `
        -TerraformFlows $TerraformFlows `
        -ExportedFlows $ExportedFlows `
        -SkippedFlows $SkippedFlows

    Write-Success "Backup validation completed."


    # -----------------------------------------------------------------------
    # Completion
    # -----------------------------------------------------------------------

    $EndTime = Get-Date

    Write-Host ""
    Write-Host "================================================================" `
        -ForegroundColor Green
    Write-Host "EXPORT COMPLETED SUCCESSFULLY" `
        -ForegroundColor Green
    Write-Host "================================================================" `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "Backup:"
    Write-Host "  $BackupDirectory"

    Write-Host ""
    Write-Host "Terraform flows discovered:"
    Write-Host "  $($TerraformFlows.Count)"

    Write-Host ""
    Write-Host "Archy flows exported:"
    Write-Host "  $($ExportedFlows.Count)"

    Write-Host ""
    Write-Host "Flows skipped:"
    Write-Host "  $($SkippedFlows.Count)"

    Write-Host ""
    Write-Host "Duration:"
    Write-Host "  $([math]::Round(($EndTime - $StartTime).TotalSeconds, 2)) seconds"
    Write-Host ""

}
catch {

    Write-Host ""
    Write-Failure "EXPORT FAILED"
    Write-Host ""
    Write-Host $_.Exception.Message -ForegroundColor Red
    Write-Host ""

    Write-Host "Existing backups have not been modified." `
        -ForegroundColor Yellow

    Write-Host ""

    exit 1
}