# Customer Genesys Cloud Export

Reusable Genesys Cloud backup/export project using Terraform, Archy, and PowerShell.

## Purpose

`run-export.ps1` is the single entry point for exporting Genesys Cloud configuration and Architect flows, validating the result, and creating an immutable timestamped backup.

The process is:

1. Validate prerequisites.
2. Clean the working Terraform and Archy export directories.
3. Run the Terraform export.
4. Read the Terraform `genesyscloud_flow` export to discover Architect flows.
5. Export supported Architect flows with Archy.
6. Validate the working exports.
7. Create a timestamped backup.
8. Validate the backup.
9. Write `export-metadata.json`.

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
│   └── export/
├── archy/
│   ├── config/
│   │   └── options.yaml
│   ├── export/
│   └── archy-home/
├── tools/
│   ├── terraform/
│   │   └── terraform.exe
│   └── archy/
│       └── archy.exe
└── backups/
    └── YYYYMMDD-HHmmss/
        ├── terraform/
        ├── archy/
        └── export-metadata.json
```

Terraform owns `terraform/export/`. Archy owns `archy/export/`. PowerShell owns the backup lifecycle.

## Prerequisites

- Windows PowerShell.
- Customer Genesys Cloud OAuth client.
- Required OAuth permissions.
- Bundled Terraform executable under `tools/terraform/terraform.exe`.
- Bundled Archy executable under `tools/archy/archy.exe`.
- Customer-specific Terraform configuration.

## OAuth Configuration

**The OAuth credentials must be configured in two places.**

### Archy

Update:

```text
archy/config/options.yaml
```

with the customer's:

- Client ID
- Client Secret

### Terraform

Update:

```text
terraform/oauth.auto.tfvars
```

with the customer's:

- Client ID
- Client Secret

Updating one file does **not** update the other. Both must be configured for the complete export process to work.

Treat both files as secret-bearing configuration and do not commit customer credentials to source control.

## OAuth Role

The supplied Terraform role export defines:

```text
NTT-backup-Read-Only-Access
```

Description:

```text
Used for Terraform and Archy backup processes
```

The supplied role is read-only and uses `view` permissions.

The reference role export is:

```text
genesyscloud_auth_role.tf.json
```

### Permissions

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

These permissions cover the resources required by the Terraform and Archy backup processes represented by the supplied role export.

## Running the Export

From the project root:

```powershell
.\run-export.ps1
```

The script handles the complete export and backup workflow.

## Terraform Export

Terraform is the source of truth for the Genesys Cloud configuration export.

Working export:

```text
terraform/export/
```

The Architect flow resource export is:

```text
terraform/export/flow/genesyscloud_flow.tf.json
```

The script reads this JSON to discover the actual Genesys Cloud flow names and types rather than maintaining a hard-coded list of flow names.

## Archy Export

Archy writes Architect flow YAML files to:

```text
archy/export/
```

Supported flow types are controlled by `$ArchySupportedFlowTypes` in `run-export.ps1`.

Current supported types in the supplied script:

- `inboundcall`
- `bot`
- `commonmodule`

The actual Genesys flow name is passed to Archy unchanged. Generated YAML filenames are prefixed with the flow type, for example:

```text
inboundcall_AlexL Customer Support_v1-0.yaml
```

## Backups

Successful exports are stored under:

```text
backups/YYYYMMDD-HHmmss/
```

Example:

```text
backups/
└── 20260929-134225/
    ├── terraform/
    ├── archy/
    └── export-metadata.json
```

Working export directories are cleaned on a new run. Existing timestamped backups are retained.

## Export Metadata

Each backup contains:

```text
export-metadata.json
```

The metadata records the export timestamps and duration, Terraform flow/resource counts, Archy exported/skipped counts, supported flow types, and the exported/skipped flow details.

## Failure Behaviour

A failure in Terraform, Archy, or backup validation causes the overall export to fail.

Existing timestamped backups are left untouched.

A failed run may leave partial content in the working export directories. These directories are cleaned at the beginning of the next run.

## Special Characters in Flow Names

Flow names are passed to Archy as the actual Genesys Cloud flow name. The name should not be sanitised before the Archy call, because changing it could prevent Archy from identifying the correct flow.

Filename handling is separate from the flow name used for the Archy request.

## New Customer Setup

1. Create the customer repository from this project.
2. Create/configure the Genesys Cloud OAuth client.
3. Ensure the OAuth client has the permissions represented by `NTT-backup-Read-Only-Access`.
4. Update `archy/config/options.yaml` with the Client ID and Client Secret.
5. Update `terraform/oauth.auto.tfvars` with the Client ID and Client Secret.
6. Configure the customer-specific Terraform settings.
7. Confirm the bundled Terraform and Archy executables exist.
8. Run:

```powershell
.\run-export.ps1
```

9. Verify that a new timestamped directory exists under `backups/`.
10. Review `export-metadata.json` for the export summary.

## Security

The following files contain customer-specific OAuth credentials:

```text
archy/config/options.yaml
terraform/oauth.auto.tfvars
```

Do not commit OAuth secrets to a public repository.

The `backups/` directory contains exported customer Genesys Cloud configuration and should be treated as customer-confidential data.

## Troubleshooting

### Terraform authentication fails

Check `terraform/oauth.auto.tfvars` and verify the Client ID, Client Secret, Genesys Cloud region, and OAuth permissions.

### Archy authentication fails

Check `archy/config/options.yaml` and verify the Client ID and Client Secret.

Remember that Terraform and Archy have separate configuration files.

### A flow is skipped

Check the flow type in:

```text
terraform/export/flow/genesyscloud_flow.tf.json
```

Only flow types configured in `$ArchySupportedFlowTypes` are passed to Archy. Skipped flows are recorded in `export-metadata.json`.

### Backup validation fails

Review the preceding export output for the first failure. Existing timestamped backups should remain unchanged.

## Design Principles

- Terraform is the source of truth for the Genesys Cloud configuration export.
- Architect flows are exported through Archy.
- Flow discovery is data-driven from the Terraform flow export.
- Working exports and historical backups are kept separate.
- Backups are timestamped and are not overwritten by later runs.
- OAuth credentials are configured separately for Terraform and Archy.
- The OAuth role used for backup access is read-only.
