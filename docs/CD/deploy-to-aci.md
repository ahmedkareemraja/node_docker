# Deploying to Azure Container Instances (ACI) via the CD Pipeline

This picks up *after* authentication. It assumes the workflow has already
run an `azure/login` step using one of:

- [oidc-authentication.md](oidc-authentication.md)
- [service-principal-authentication.md](service-principal-authentication.md)

Either auth method works identically from this point on — everything below
is just `az`/`docker` commands running as whatever identity logged in.

## The flow

```
checkout → azure/login → az acr login → docker build & push → az container create (redeploy)
```

1. Log in to the ACR with the identity from `azure/login` (no separate
   registry password needed for the *push*).
2. Build the image and tag it with the git commit SHA — not `latest`. A
   unique tag per run is what lets you tell which commit is actually
   running in ACI, and lets you roll back by redeploying an older tag.
3. Push the image to ACR.
4. Point the ACI container group at the new image tag.

## One-time setup

The identity used for `azure/login` needs push rights on the registry
(if you haven't already granted this per the note in
[service-principal-authentication.md](service-principal-authentication.md)):

```
az role assignment create \
  --assignee <appId> \
  --role AcrPush \
  --scope /subscriptions/<sub-id>/resourceGroups/<rg>/providers/Microsoft.ContainerRegistry/registries/<acr-name>
```

ACI also needs a way to *pull* from the registry at container-start time.
The simplest option for a learning project is the registry's built-in
admin account:

```
az acr update --name <acr-name> --admin-enabled true
```

(This is a shared username/password on the registry itself, separate from
your pipeline's identity. It's the quickest way to get ACI pulling images.
The more production-grade approach is assigning ACI a managed identity
with `AcrPull` instead of using the admin account — worth exploring once
the basic pipeline works, but not covered here.)

## Step-by-step

### 1. Log in to the ACR
```yaml
- name: Log in to ACR
  run: az acr login --name <acr-name>
```

### 2. Build and tag the image
```yaml
- name: Build and push image
  run: |
    docker build -t <acr-name>.azurecr.io/node-app:${{ github.sha }} .
    docker push <acr-name>.azurecr.io/node-app:${{ github.sha }}
```

### 3. Fetch the ACR admin credentials for ACI to use
```yaml
- name: Get ACR credentials
  id: acr-creds
  run: |
    echo "username=$(az acr credential show -n <acr-name> --query username -o tsv)" >> "$GITHUB_OUTPUT"
    echo "password=$(az acr credential show -n <acr-name> --query 'passwords[0].value' -o tsv)" >> "$GITHUB_OUTPUT"
```
These are fetched fresh on every run rather than stored as a GitHub
secret, so there's nothing extra to rotate manually.

### 4. Redeploy the ACI container group
```yaml
- name: Deploy to Azure Container Instances
  run: |
    az container create \
      --resource-group <resource-group> \
      --name node-app \
      --image <acr-name>.azurecr.io/node-app:${{ github.sha }} \
      --registry-login-server <acr-name>.azurecr.io \
      --registry-username ${{ steps.acr-creds.outputs.username }} \
      --registry-password ${{ steps.acr-creds.outputs.password }} \
      --os-type Linux \
      --cpu 1 --memory 1 \
      --ports 3000 \
      --environment-variables PORT=3000 \
      --dns-name-label <your-unique-dns-label>
```

**On re-running `az container create` against an existing container
group:** this command is idempotent for most property changes (like the
image tag) — running it again with the same `--name`/`--resource-group`
redeploys the group in place. If Azure CLI ever rejects the update because
you're changing something it can't modify in place (e.g. OS type,
networking), delete and recreate instead:
```
az container delete --resource-group <resource-group> --name node-app --yes
az container create ...   # same command as above
```

Note that either path causes a brief gap where the container group isn't
running (ACI doesn't do rolling/zero-downtime redeploys) — expected for a
single-instance ACI setup, not something to debug if you see a few
seconds of downtime on deploy.

## Full example jobs

Everything after the `azure/login` step is identical for both auth
approaches — only the login step itself differs. Two complete, standalone
versions below so you can copy-paste either one directly rather than
toggling a commented-out line.

### Using OIDC auth

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      id-token: write   # required for OIDC
      contents: read
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Log in to ACR
        run: az acr login --name <acr-name>

      - name: Build and push image
        run: |
          docker build -t <acr-name>.azurecr.io/node-app:${{ github.sha }} .
          docker push <acr-name>.azurecr.io/node-app:${{ github.sha }}

      - name: Get ACR credentials
        id: acr-creds
        run: |
          echo "username=$(az acr credential show -n <acr-name> --query username -o tsv)" >> "$GITHUB_OUTPUT"
          echo "password=$(az acr credential show -n <acr-name> --query 'passwords[0].value' -o tsv)" >> "$GITHUB_OUTPUT"

      - name: Deploy to Azure Container Instances
        run: |
          az container create \
            --resource-group <resource-group> \
            --name node-app \
            --image <acr-name>.azurecr.io/node-app:${{ github.sha }} \
            --registry-login-server <acr-name>.azurecr.io \
            --registry-username ${{ steps.acr-creds.outputs.username }} \
            --registry-password ${{ steps.acr-creds.outputs.password }} \
            --os-type Linux \
            --cpu 1 --memory 1 \
            --ports 3000 \
            --environment-variables PORT=3000 \
            --dns-name-label <your-unique-dns-label>
```

Uses the identity set up in [oidc-authentication.md](oidc-authentication.md)
— requires `id-token: write` in `permissions` and the `AZURE_CLIENT_ID`,
`AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` secrets, no long-lived secret
for the Azure login itself.

### Using service principal + secret auth

```yaml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v2
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}

      - name: Log in to ACR
        run: az acr login --name <acr-name>

      - name: Build and push image
        run: |
          docker build -t <acr-name>.azurecr.io/node-app:${{ github.sha }} .
          docker push <acr-name>.azurecr.io/node-app:${{ github.sha }}

      - name: Get ACR credentials
        id: acr-creds
        run: |
          echo "username=$(az acr credential show -n <acr-name> --query username -o tsv)" >> "$GITHUB_OUTPUT"
          echo "password=$(az acr credential show -n <acr-name> --query 'passwords[0].value' -o tsv)" >> "$GITHUB_OUTPUT"

      - name: Deploy to Azure Container Instances
        run: |
          az container create \
            --resource-group <resource-group> \
            --name node-app \
            --image <acr-name>.azurecr.io/node-app:${{ github.sha }} \
            --registry-login-server <acr-name>.azurecr.io \
            --registry-username ${{ steps.acr-creds.outputs.username }} \
            --registry-password ${{ steps.acr-creds.outputs.password }} \
            --os-type Linux \
            --cpu 1 --memory 1 \
            --ports 3000 \
            --environment-variables PORT=3000 \
            --dns-name-label <your-unique-dns-label>
```

Uses the identity set up in
[service-principal-authentication.md](service-principal-authentication.md)
— no `id-token: write` needed since there's no OIDC token exchange, just
the single `AZURE_CREDENTIALS` JSON secret.

Note: both jobs deploy to the *same* `--name node-app` container group and
`--dns-name-label`. If you want to actually run both side by side to
compare them (rather than just swapping which workflow is active), give
the service-principal version a different `--name` (e.g. `node-app-sp`)
and `--dns-name-label` so they don't fight over the same ACI resource.

## Placeholders to fill in

| Placeholder | Where to get it |
|---|---|
| `<acr-name>` | Your existing ACR's name (no `.azurecr.io` suffix) |
| `<resource-group>` | The resource group your ACR/ACI already live in |
| `<your-unique-dns-label>` | Must be globally unique across all of Azure — pick something like `node-app-<your-name>` |
| `--cpu` / `--memory` / `--ports` | Match whatever you used when creating the container instance manually via CLI/portal |
