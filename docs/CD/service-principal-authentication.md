# Azure Auth for CD: Service Principal with Client Secret (Classic)

Replaces `az login` in GitHub Actions with a robot-account username/password
pair, stored as a GitHub secret. Closer to how `az login` works locally —
you're logging in as a distinct identity with a credential, rather than
exchanging a short-lived token.

## One-time setup — CLI (run locally, needs `az login` + Owner/User Access Administrator on the subscription or resource group)

1. Create the service principal and role assignment in one command:
   ```
   az ad sp create-for-rbac \
     --name "node-app-cd" \
     --role contributor \
     --scopes /subscriptions/<subscription-id>/resourceGroups/<resource-group> \
     --sdk-auth
   ```

2. This prints a JSON blob:
   ```json
   {
     "clientId": "...",
     "clientSecret": "...",
     "subscriptionId": "...",
     "tenantId": "..."
   }
   ```
   `clientSecret` is a real password — treat the terminal output as
   sensitive and don't leave it in shell history longer than necessary.

3. Copy the entire JSON blob into a single GitHub secret, e.g.
   `AZURE_CREDENTIALS` (GitHub → repo → Settings → Secrets and variables →
   Actions).

## One-time setup — Azure Portal (equivalent, no CLI)

The portal doesn't have a single button that produces the `--sdk-auth` JSON
blob — you create the same underlying objects individually and assemble
the JSON yourself.

1. Create the App Registration:
   - Go to **portal.azure.com** → search **"App registrations"** (under
     Microsoft Entra ID) → **New registration**.
   - Name: `node-app-cd`. Leave "Supported account types" on the default.
     Leave "Redirect URI" blank. Click **Register**.

2. From the app's **Overview** page, copy:
   - **Application (client) ID** → this becomes `clientId`
   - **Directory (tenant) ID** → this becomes `tenantId`

3. Create the client secret:
   - Left menu → **Certificates & secrets** → **Client secrets** tab →
     **New client secret**.
   - Add a description and an expiry (e.g. 6 or 12 months).
   - Click **Add**, then **immediately copy the "Value" column** — this is
     your `clientSecret`. It is shown only once; if you navigate away
     before copying it, you must create a new secret.

4. Grant the app a role on your resource group:
   - Go to your **Resource group** (or the Subscription) → **Access
     control (IAM)** → **Add** → **Add role assignment**.
   - Role: **Contributor** → Next.
   - Members: "Assign access to" → **User, group, or service principal** →
     **Select members** → search `node-app-cd` → select it → **Review +
     assign**.

5. Get the subscription ID from the **Subscriptions** blade → copy the
   **Subscription ID** → this becomes `subscriptionId`.

6. Assemble the JSON yourself, matching the shape the CLI's `--sdk-auth`
   would have produced:
   ```json
   {
     "clientId": "<Application (client) ID>",
     "clientSecret": "<the secret Value you copied>",
     "subscriptionId": "<Subscription ID>",
     "tenantId": "<Directory (tenant) ID>"
   }
   ```

7. Paste that JSON into a single GitHub secret, `AZURE_CREDENTIALS`
   (GitHub → repo → **Settings** → **Secrets and variables** → **Actions**
   → **New repository secret**).

## Workflow usage

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      # From here on, `az` CLI commands in the workflow run as this
      # identity, same as after:
      # az login --service-principal -u <clientId> -p <clientSecret> --tenant <tenantId>
```

## Rotating / revoking

The secret does not expire immediately, but Azure AD app secrets have a
default expiry (commonly 1–2 years, configurable at creation). Before it
expires:

```
az ad sp credential reset --name "node-app-cd"
```

...and update the `AZURE_CREDENTIALS` GitHub secret with the new output. If
the secret ever leaks, revoke it immediately with the same command (it
invalidates the old one) or `az ad sp delete --id <appId>` to remove the
service principal entirely.

**Portal equivalent:** open the app registration → **Certificates &
secrets** → **Client secrets** → **New client secret** to issue a
replacement, then delete the old one (bin icon next to it) once the new
value is saved in the `AZURE_CREDENTIALS` GitHub secret. To revoke
immediately, just delete the compromised secret from that list — no
replacement needs to exist first.

## Trade-offs

- **Pro:** simplest mental model — one secret, one login step, matches
  local `az login --service-principal` almost exactly.
- **Con:** `clientSecret` is a long-lived bearer credential. Anyone who
  obtains it can authenticate as this service principal from anywhere,
  not just from GitHub Actions, until it's rotated or revoked. You are
  responsible for remembering to rotate it before expiry.
