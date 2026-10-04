# Azure Auth for CD: OIDC Federated Credential (Recommended)

Replaces `az login` in GitHub Actions with no stored password. GitHub mints a
short-lived signed token proving "this run belongs to this repo/branch";
Azure AD trusts that token only if it matches a federated credential you
configure once, and hands back a short-lived Azure access token in return.

## One-time setup — CLI (run locally, needs `az login` + Owner/User Access Administrator on the subscription or resource group)

1. Create an App Registration and its service principal:
   ```
   az ad app create --display-name "node-app-cd"
   # note the appId from the output, then:
   az ad sp create --id <appId>
   ```

2. Grant that service principal a role over the resource group your app lives in:
   ```
   az role assignment create \
     --assignee <appId> \
     --role contributor \
     --scope /subscriptions/<subscription-id>/resourceGroups/<resource-group>
   ```

3. Add a federated credential scoped to this repo's `main` branch:
   ```
   az ad app federated-credential create --id <appId> --parameters '{
     "name": "node-app-main-branch",
     "issuer": "https://token.actions.githubusercontent.com",
     "subject": "repo:<github-org-or-user>/node-app:ref:refs/heads/main",
     "audiences": ["api://AzureADTokenExchange"]
   }'
   ```
   The `subject` is the important part — it pins trust to pushes on `main` in
   this exact repo. If you later want PRs or other branches to authenticate
   too, add additional federated credentials with different `subject` values
   (e.g. `repo:<org>/node-app:pull_request`).

4. Note three values for GitHub secrets (all non-secret identifiers, not passwords):
   - `AZURE_CLIENT_ID` — the `appId` from step 1
   - `AZURE_TENANT_ID` — from `az account show --query tenantId -o tsv`
   - `AZURE_SUBSCRIPTION_ID` — from `az account show --query id -o tsv`

   Add them at GitHub → repo → Settings → Secrets and variables → Actions.

## One-time setup — Azure Portal (equivalent, no CLI)

1. Create the App Registration:
   - Go to **portal.azure.com** → search **"App registrations"** (this
     lives under Microsoft Entra ID) → **New registration**.
   - Name: `node-app-cd`. Leave "Supported account types" on the default
     (single tenant). Leave "Redirect URI" blank. Click **Register**.

2. Grab the two identifiers from the app's **Overview** page:
   - **Application (client) ID** → this is your `AZURE_CLIENT_ID`
   - **Directory (tenant) ID** → this is your `AZURE_TENANT_ID`

3. Add the federated credential:
   - In the app's left menu, go to **Certificates & secrets** →
     **Federated credentials** tab → **Add credential**.
   - Federated credential scenario: **GitHub Actions deploying Azure
     resources**.
   - Organization: your GitHub org/username. Repository: `node-app`.
   - Entity type: **Branch**. GitHub branch name: `main`.
   - Name: `node-app-main-branch` → **Add**.
   - (Optional, later) repeat this with entity type **Pull request** if you
     also want workflow runs on PRs to authenticate.

4. Grant the app a role on your resource group:
   - Go to your **Resource group** (or the Subscription, for broader
     scope) → **Access control (IAM)** → **Add** → **Add role assignment**.
   - Role: **Contributor** → Next.
   - Members: "Assign access to" → **User, group, or service principal** →
     **Select members** → search `node-app-cd` → select it → **Review +
     assign**.

5. Get the subscription ID:
   - Go to **Subscriptions** in the portal, copy the **Subscription ID**
     shown next to your subscription → this is your `AZURE_SUBSCRIPTION_ID`.

6. Add the three secrets (`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`,
   `AZURE_SUBSCRIPTION_ID`) at GitHub → repo → **Settings** → **Secrets and
   variables** → **Actions** → **New repository secret**.

## Workflow usage

```yaml
permissions:
  id-token: write   # required so the job can request an OIDC token
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      # From here on, `az` CLI commands in the workflow run as this
      # identity, same as after a local `az login`.
```

## Trade-offs

- **Pro:** nothing long-lived to leak or rotate; access is cryptographically
  tied to this exact repo + branch.
- **Con:** more moving parts to understand up front (App Registration,
  service principal, federated credential are three distinct Azure AD
  objects), and mistakes in the `subject` field fail silently with an
  auth error until it matches exactly.
