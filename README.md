# Azure Logs Ingestion API Troubleshooter

**A step-by-step troubleshooting toolkit for the [Azure Monitor Logs Ingestion API](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-ingestion-api-overview)** — built as a [Bruno](https://www.usebruno.com/) collection.

Diagnose and fix Data Collection Rule (DCR) stream declaration mismatches, column misalignments, and ingestion failures when sending custom log data via the **Logs Ingestion API (REST/HTTP)**.

> **Scope:** This tool is specifically for the **Logs Ingestion API** — the REST API used to send custom data to Log Analytics via Data Collection Rules (DCRs). It is **not** for troubleshooting the Azure Monitor Agent (AMA), which uses DCRs differently for agent-based data collection.

![Bruno](https://img.shields.io/badge/Built%20for-Bruno%20API%20Client-yellow)
![License](https://img.shields.io/badge/License-MIT-blue)
![Azure](https://img.shields.io/badge/Azure-Logs%20Ingestion%20API-0078D4)

---

## The Problem

The [Logs Ingestion API](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-ingestion-api-overview) lets you send custom log data to Azure Monitor Log Analytics workspaces via HTTP. It requires several components to work together:

```
Your Source Data (JSON) → HTTP POST → DCR/DCE Endpoint → Stream Declarations → Transform KQL → Table_CL
```

When something goes wrong, users get cryptic HTTP error codes (403, 404, 413) or — worse — **silent failures where data simply never appears**. The most common root cause: **column mismatches between your source JSON payload and the DCR's `streamDeclarations`**.

### Common mistakes this tool catches

| Mistake | What happens | This tool shows |
|---------|-------------|-----------------|
| Column name typo (`Timestamp` vs `Time`) | Data silently dropped | `MISSING: "Time" — required by DCR but not in payload` |
| Wrong column type (string vs datetime) | Ingestion error | `DCR expects 'datetime' — Value is not a valid datetime` |
| Extra columns in payload | Silently ignored | `EXTRA: "Level" — in payload but not in DCR` |
| Missing `_CL` suffix on table name | 404 error | `Custom tables must end with '_CL' suffix` |
| Wrong stream name format | 404 error | `Stream = 'Custom-TableName' (NOT 'Custom-TableName_CL')` |
| Missing Monitoring Metrics Publisher role | 403 error | Step-by-step RBAC fix instructions |
| Payload exceeds 1 MB | 413 error | Batch splitting guidance |
| Rate limiting | 429 error | Retry-After value displayed |

---

## Prerequisites

1. **[Bruno](https://www.usebruno.com/downloads)** — Free, open-source API client (download and install)
2. **Azure resources** already configured:
   - A Log Analytics workspace
   - A Data Collection Rule (DCR) with stream declarations
   - A Microsoft Entra ID (Azure AD) app registration with a client secret

If you haven't set up these resources yet, follow the [official Logs Ingestion API tutorial](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/tutorial-logs-ingestion-portal).

---

## Quick Start

### 1. Clone this repository

```bash
git clone https://github.com/el-bakkali/azure-logs-ingestion-api-troubleshooter.git
```

### 2. Open in Bruno

1. Launch Bruno
2. Click **Open Collection**
3. Navigate to the cloned folder and select the `collection` directory

### 3. Configure your environment

1. In Bruno, click the **Environments** dropdown (top-right)
2. Select **Azure**
3. Fill in your values:

| Variable | Description | Example |
|----------|-------------|---------|
| `tenantId` | Azure AD tenant ID | `aaaabbbb-0000-cccc-1111-dddd2222eeee` |
| `clientId` | App registration Application ID | `00001111-aaaa-2222-bbbb-3333cccc4444` |
| `clientSecret` | App registration secret value | `Aa1Bb~2Cc3.Dd4Ee5Ff6Gg7Hh8` |
| `subscriptionId` | Azure subscription ID | `aaaa0a0a-bb1b-cc2c-dd3d-eeeeee4e4e4e` |
| `resourceGroup` | Resource group containing the DCR | `rg-monitoring` |
| `workspaceName` | Log Analytics workspace name | `my-workspace` |
| `dcrImmutableId` | DCR immutable ID | `dcr-00000000000000000000000000000000` |
| `ingestionEndpoint` | DCR or DCE logs ingestion endpoint | `https://my-dce.eastus-1.ingest.monitor.azure.com` |
| `streamName` | Stream name in the DCR | `Custom-MyTable` |
| `tableName` | Destination table name (with `_CL`) | `MyTable_CL` |
| `armBaseUrl` | Azure Resource Manager base URL | `https://management.azure.com` |

### 4. Run the steps in order

Execute each request sequentially — click the request name and press **Send**:

```
1-Authenticate/
  ├── Get Bearer Token        ← Token for Ingestion API
  └── Get ARM Token           ← Token for fetching DCR/table definitions

2-Inspect-DCR/
  └── Fetch DCR Definition    ← Lists all DCRs, shows stream columns & transforms

3-Fetch-Table-Schema/
  └── Get Table Columns       ← Shows destination table schema

4-Validate-Payload/
  └── Schema Diff Check       ← Compares your payload against DCR schema

5-Test-Ingestion/
  └── Send Test Data          ← Sends 2 test records with diagnostics

6-Query-Results/
  └── Check Data Arrived      ← Queries Log Analytics to verify data landed
```

---

## What Each Step Does

### Step 1: Authenticate

Acquires two OAuth2 tokens using client credentials flow:
- **Bearer Token** — for the Logs Ingestion API (`https://monitor.azure.com//.default`)
- **ARM Token** — for Azure Resource Manager API (`https://management.azure.com//.default`) to read DCR and table definitions

### Step 2: Inspect DCR

Fetches all Data Collection Rules in your resource group and displays:
- Stream declarations with column names and types
- Data flow configuration (source streams → destination tables)
- Transform KQL query
- Ingestion endpoint URL

### Step 3: Fetch Table Schema

Retrieves the destination table definition from your Log Analytics workspace:
- All columns with their types
- Retention settings
- System vs custom columns

### Step 4: Validate Payload (Schema Diff)

**The core troubleshooting step.** Before sending data, this performs a pre-flight check:

1. Parses the JSON body you're about to send
2. Compares each field against the DCR's stream declarations
3. Reports:
   - **Matched columns** — present in both payload and DCR
   - **Missing columns** — required by DCR but absent from payload
   - **Extra columns** — in payload but not in DCR (will be ignored)
   - **Type mismatches** — wrong data type (e.g., string where datetime expected)
4. Generates a fix template with example values for missing columns
5. Then sends the request and explains any error codes

**Edit the request body** in this step to match your actual data before running it.

### Step 5: Send Test Data

Sends 2 clearly-labeled test records (`TroubleshooterTest-1`, `TroubleshooterTest-2`) to verify end-to-end ingestion. These records are easy to find later when querying.

### Step 6: Query Results

Queries your Log Analytics workspace for the test records to confirm data arrived successfully. If found, prints a full validation summary.

---

## Troubleshooting Reference

### Error Codes

| Error | Meaning | Fix |
|-------|---------|-----|
| **HTTP 204** | Success — data accepted | Wait 5-15 min for data to appear in table |
| **HTTP 400** | Bad request — invalid payload format | Body must be JSON array `[{...}]`, check column names/types |
| **HTTP 403** | Permission denied | Assign **Monitoring Metrics Publisher** role to your app on the DCR. Wait up to 30 min for propagation |
| **HTTP 404** | DCR, stream, or endpoint not found | Verify `dcrImmutableId`, `streamName` (format: `Custom-TableName` without `_CL`), and endpoint URL |
| **HTTP 413** | Payload too large (>1 MB) | Split data into smaller batches |
| **HTTP 429** | Rate limit exceeded | Wait per `Retry-After` header. Limits: 500 MB/min, 300K requests/min |
| **`RecordsTimeRangeIsMoreThan30Minutes`** | Timestamps span >30 min | Group records into batches within 30-min windows. Does not apply to Auxiliary logs with transforms |

### Data Not Appearing

| Symptom | Cause | Resolution |
|---------|-------|------------|
| No data after 15 min | First-time ingestion delay | Wait up to 15 minutes, especially for new tables |
| IntelliSense doesn't show table | Cache delay | IntelliSense cache can take up to 24 hours to update |
| HTTP 204 but no data | Column mismatch in DCR | Run Step 4 (Schema Diff) to identify mismatches |
| Data appears with wrong columns | Transform KQL issue | Check the `transformKql` in your DCR definition (Step 2) |

### Stream Name vs Table Name

This is the **#1 source of confusion**:

| Concept | Format | Example |
|---------|--------|---------|
| **Table name** (in Log Analytics) | `TableName_CL` | `MyTable_CL` |
| **Stream name** (in DCR & API call) | `Custom-TableName` | `Custom-MyTable` |
| **Output stream** (in DCR dataFlows) | `Custom-TableName_CL` | `Custom-MyTable_CL` |

---

## How the Logs Ingestion API Works

The Logs Ingestion API is a **REST endpoint** — you POST JSON data over HTTP to a Data Collection Rule (DCR) or Data Collection Endpoint (DCE). This is distinct from the Azure Monitor Agent (AMA), which collects data from VMs and uses DCRs in a different way.

```
┌──────────────┐     ┌──────────────────┐     ┌───────────────┐     ┌──────────────┐
│  Your Source  │────▶│  DCR/DCE         │────▶│  Transform    │────▶│  Table_CL    │
│  (JSON array) │     │  Endpoint        │     │  (KQL query)  │     │  (Log        │
│  via HTTP     │     │  /streams/Custom-│     │              │     │  Analytics)  │
│  POST         │     │  TableName       │     │              │     │              │
└──────────────┘     └──────────────────┘     └───────────────┘     └──────────────┘
       │                      │                       │                      │
   Your data            Stream validates         Transform maps        Final storage
   as JSON array        columns against          & filters data        with _CL suffix
                        streamDeclarations
```

### Components

| Component | Purpose | Where to find it |
|-----------|---------|-----------------|
| **App Registration** | OAuth2 authentication | Azure Portal → Microsoft Entra ID → App Registrations |
| **DCR** (Data Collection Rule) | Defines expected schema, transform, and destination | Azure Portal → Monitor → Data Collection Rules |
| **DCE** (Data Collection Endpoint) | HTTP endpoint that receives Logs Ingestion API data (optional if DCR has built-in endpoint) | Azure Portal → Monitor → Data Collection Endpoints |
| **Stream Declaration** | Column definitions for incoming data | Inside DCR JSON → `properties.streamDeclarations` |
| **Transform KQL** | Kusto query to filter/reshape data before storage | Inside DCR JSON → `properties.dataFlows[].transformKql` |
| **Custom Table** | Destination table in Log Analytics (must end with `_CL`) | Azure Portal → Log Analytics → Tables |

---

## Adapting to Your Schema

The collection ships with a sample schema matching the [official Azure tutorial](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/tutorial-logs-ingestion-api) (`Time`, `Computer`, `AdditionalContext`).

**To use your own schema:**

1. Run Steps 1-2 to authenticate and fetch your DCR definition
2. Note the column names and types from the console output
3. Edit the request body in **Step 4 (Schema Diff Check)** and **Step 5 (Send Test Data)** to match your actual data structure
4. Run Steps 4-6 to validate and test

---

## Project Structure

```
azure-logs-ingestion-api-troubleshooter/
├── README.md
├── LICENSE
├── collection/
│   ├── bruno.json                              ← Collection config
│   ├── environments/
│   │   └── Azure.bru                           ← Your credentials & settings
│   ├── 1-Authenticate/
│   │   ├── Get Bearer Token.bru                ← Ingestion API token
│   │   └── Get ARM Token.bru                   ← ARM API token
│   ├── 2-Inspect-DCR/
│   │   └── Fetch DCR Definition.bru            ← List & inspect DCRs
│   ├── 3-Fetch-Table-Schema/
│   │   └── Get Table Columns.bru               ← Table column definitions
│   ├── 4-Validate-Payload/
│   │   └── Schema Diff Check.bru               ← Schema comparison engine
│   ├── 5-Test-Ingestion/
│   │   └── Send Test Data.bru                  ← Send labeled test records
│   └── 6-Query-Results/
│       └── Check Data Arrived.bru              ← Verify data in table
```

---

## Related Resources

- [Logs Ingestion API Overview](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/logs-ingestion-api-overview)
- [Tutorial: Send data via Azure Portal](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/tutorial-logs-ingestion-portal)
- [Tutorial: Send data via ARM Templates](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/tutorial-logs-ingestion-api)
- [Sample code (.NET, Python, Java, JS, Go, PowerShell)](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/tutorial-logs-ingestion-code)
- [Set up prerequisites (PowerShell script)](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/set-up-logs-ingestion-api-prerequisites)
- [Data Collection Rule structure](https://learn.microsoft.com/en-us/azure/azure-monitor/essentials/data-collection-rule-structure)
- [Bruno API Client](https://www.usebruno.com/)

---

## Contributing

Contributions welcome! Feel free to:
- Add new troubleshooting checks
- Improve error messages
- Add support for additional Logs Ingestion API scenarios (e.g., built-in table ingestion)
- Report common misconfiguration patterns you've encountered

---

## License

[MIT](LICENSE)
