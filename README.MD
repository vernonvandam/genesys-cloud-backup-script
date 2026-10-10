# Customer Genesys Cloud Export

Reusable Genesys Cloud configuration export and backup project using Terraform and PowerShell.

## Purpose

`run-export.ps1` is the single entry point for exporting Genesys Cloud configuration, validating the exported files, and creating an immutable timestamped backup.

Terraform exports Architect flows directly as YAML. Archy is not required.

The process is:

1. Validate the Terraform executable and project directories.
2. Clean the working Terraform export directory.
3. Run Terraform initialisation and export.
4. Validate the Terraform export and identify generated YAML files.
5. Create a timestamped backup with exported files copied directly into the backup directory.
6. Compare source and backup file manifests using SHA-256 hashes.
7. Write `export-metadata.json`.

Existing timestamped backups are not modified or deleted by a subsequent run.

## Repository Structure

```text
customer-genesys-cloud-export/
├── run-export.ps1
├── terraform/
│   ├── main.tf
│   ├── provider.tf
│   ├── variables.tf
│   ├── terraform.tfvars
│   ├── oauth.auto.tfvars
│   ├── modules/
│   └── export/                 # Working export; recreated on each run
├── tools/
│   └── terraform/
│       └── terraform.exe
└── backups/
    └── YYYYMMDD-HHmmss/
        ├── ... exported files and directories ...
        └── export-metadata.json
```

Terraform owns the working `terraform/export/` directory. PowerShell manages the export run, backup lifecycle, hash verification, and metadata.

## Prerequisites

- Windows PowerShell 5.1 or later.
- A Genesys Cloud OAuth client with the required read permissions.
- Terraform executable at `tools/terraform/terraform.exe`.


## OAuth Configuration

Configure the customer OAuth credentials in:

```text
terraform/oauth.auto.tfvars
```

Supply the customer-specific values required by the Terraform configuration, including the OAuth Client ID and Client Secret.

Treat this file as secret-bearing configuration. Do not commit customer credentials to source control. The repository `.gitignore` should exclude `terraform/oauth.auto.tfvars`.

## OAuth Role and Permissions

The supplied Terraform role export defines the role:

```text
GC-backup-Read-Only-Access
```

The role is intended for read-only backup access and uses `view` permissions. The reference role export is:

```text
genesyscloud_auth_role.tf.json
```

The supplied role contains these permissions:

- `architect.datatable` — `view`
- `architect.datatableRow` — `view`
- `architect.dependencyTracking` — `view`
- `architect.flow` — `view`
- `architect.flowExecution` — `view`
- `architect.flowInstance` — `view`
- `architect.flowInstanceExecutionData` — `view`
- `architect.flowLogLevel` — `view`
- `architect.flowLogLevelDefault` — `view`
- `architect.flowMilestone` — `view`
- `architect.flowOutcome` — `view`
- `architect.job` — `view`
- `architect.jobExport` — `view`
- `architect.systemPrompt` — `view`
- `architect.ui` — `view`
- `architect.userPrompt` — `view`
- `authorization.division` — `view`
- `authorization.role` — `view`
- `conversation.settings` — `view`
- `integrations.action` — `view`
- `integrations.actionFunction` — `view`
- `integrations.integration` — `view`
- `messaging.setting` — `view`
- `messaging.supportedContent` — `view`
- `oauth.client` — `view`
- `routing.callRoute` — `view`
- `scripter.publishedScript` — `view`
- `scripter.script` — `view`

Review the permissions against the resources enabled in the customer-specific Terraform configuration. The permissions listed above reflect the supplied role export; this README does not assert that they are sufficient for every possible resource configuration.

## Running the Export

From the project root, run:

```powershell
.\run-export.ps1
```

The script performs Terraform initialisation and export, validates the output, creates a timestamped backup, verifies file integrity, and writes metadata.

## Terraform Export

Terraform is responsible for exporting Genesys Cloud configuration, including Architect flows as YAML.

The working export directory is:

```text
terraform/export/
```

Ensure the Terraform export configuration sets:

```hcl
use_legacy_architect_flow_exporter = false
```

The exact location of this setting depends on the Terraform configuration used by the project. Confirm it is applied to the export configuration before running the script.

The script validates that the working export directory exists and contains files. It also reports the number of YAML files found. It does not use Archy or separately discover and export individual flows.

## Backups

Successful exports are stored under:

```text
backups/YYYYMMDD-HHmmss/
```

Example:

```text
backups/
└── 20261010-080100/
    ├── flow/
    ├── ... other exported files and directories ...
    └── export-metadata.json
```

The contents of `terraform/export/` are copied directly into the timestamped backup directory. The backup does **not** add `terraform/export/` as an extra directory layer.

The timestamp uses the format `yyyyMMdd-HHmmss`. If a backup directory with that timestamp already exists, the script stops rather than overwriting it.

The working `terraform/export/` directory is cleaned at the beginning of a run. Existing timestamped backups are retained and are not modified or deleted by later runs.

## SHA-256 Integrity Verification

After copying the export into the timestamped backup directory, the script calculates SHA-256 hashes for the source export files and their corresponding backup files.

Validation compares the file manifests using relative paths, file sizes, and SHA-256 hashes. A missing file, unexpected file, size difference, or hash mismatch causes validation to fail.

This verifies that the backed-up files match the files produced by that export run. It does not prove that the original export is correct, and it does not protect the metadata or backup from a person who can modify both the files and the verification records.

## Export Metadata

Each completed backup contains:

```text
export-metadata.json
```

The metadata records export timing and duration, the export engine, export file counts, Architect YAML counts, and per-file integrity information including relative paths, file sizes, and SHA-256 hashes.

The metadata is written at the root of the timestamped backup directory. It is not part of the Terraform export manifest being compared with the source export.

## Failure Behaviour

A failure in Terraform initialisation, Terraform export, export validation, backup creation, or SHA-256 verification causes the overall run to fail.

Existing timestamped backups are left untouched. If a run fails after creating a new timestamped backup directory, that new directory may contain partial output; review it before deciding whether to remove it. The script does not delete prior backups.

A failed run may leave partial content in the working export directory. That directory is cleaned at the beginning of the next run.

## New Customer Setup

1. Create a customer-specific copy of this project.
2. Create or configure the Genesys Cloud OAuth client.
3. Ensure the OAuth client has the read permissions required by the Terraform resources being exported.
4. Update `terraform/oauth.auto.tfvars` with the customer's OAuth credentials and other required values.
5. Configure the customer-specific Terraform settings.
6. Confirm `tools/terraform/terraform.exe` exists.
7. Confirm the Terraform export configuration uses `use_legacy_architect_flow_exporter = false`.
8. Run:

   ```powershell
   .\run-export.ps1
   ```

9. Verify that a new timestamped directory exists under `backups/`.
10. Review `export-metadata.json` and confirm SHA-256 verification passed.

## Security

The following file contains customer-specific OAuth credentials:

```text
terraform/oauth.auto.tfvars
```

Do not commit OAuth secrets to a public repository. Ensure `.gitignore` excludes this file and check that it is not already tracked by Git.

The `backups/` directory contains exported Genesys Cloud configuration and should be treated as customer-confidential data. Protect it with appropriate access controls and retention policies.

## Troubleshooting

### Terraform authentication fails

Check `terraform/oauth.auto.tfvars`. Verify the Client ID, Client Secret, Genesys Cloud region, and OAuth permissions.

### Terraform export fails

Review the Terraform error output and confirm the provider configuration, credentials, permissions, and customer-specific Terraform settings are correct.

### SHA-256 backup validation fails

The script compares the source and backup file manifests. Review the reported missing, unexpected, or mismatched files. Do not treat the backup as verified until the discrepancy is resolved. Existing timestamped backups should remain unchanged.

### Backup directory already exists

The script does not overwrite an existing timestamped backup. Run the script again when the timestamp differs, or investigate whether another run has already created that directory. Do not delete a backup unless you have confirmed it is safe to remove.

## Design Principles

- Terraform is the only export engine used by this script.
- Architect flows are exported as YAML directly by Terraform.
- Working exports and historical backups are kept separate.
- Exported files are copied directly into each timestamped backup directory.
- Backups are timestamped and are not overwritten by later runs.
- SHA-256 manifests verify that backup files match the source export files.
- OAuth credentials and customer-specific configuration must not be committed to source control.
- Backup files should be treated as customer-confidential data.
