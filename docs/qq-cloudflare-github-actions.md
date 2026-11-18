# Deploy the Folia QQ Music backend with GitHub Actions

This workflow creates an isolated folia-qq-api-ios Worker in your own Cloudflare account, enables the QqQrChannel Durable Object, uploads QQ_SESSION_SECRET, resolves the account's workers.dev subdomain, then automatically triggers the iOS IPA build with the real API address injected as VITE_QQ_API_BASE.

It does not modify main and never writes the QQ session key to repository files or build artifacts.

## Add three GitHub Actions repository secrets

In the maguc98/folia-major GitHub repository, open Settings → Secrets and variables → Actions → New repository secret, then add:

| Secret name | Value |
| --- | --- |
| CLOUDFLARE_API_TOKEN | A Cloudflare API Token. Grant at least Account → Workers Scripts → Edit. This also permits reading the workers.dev subdomain. |
| CLOUDFLARE_ACCOUNT_ID | Your Cloudflare Account ID. |
| QQ_SESSION_SECRET | A random secret of at least 32 bytes. It is stored only in GitHub Secrets and Cloudflare Worker Secrets. |

Generate QQ_SESSION_SECRET locally with: openssl rand -base64 32. Do not send the generated value in chat, commit it to Git, or store it as a normal Actions Variable.

Create a Cloudflare API Token here: https://dash.cloudflare.com/profile/api-tokens. Your account must have a workers.dev subdomain enabled. The public Worker URL is generated as folia-qq-api-ios.<your-subdomain>.workers.dev.

## Run deployment and build

After adding the three secrets, open the repository's Actions tab, select "Deploy QQ Music API to Cloudflare", choose the ios/esign-ipa branch, and run the workflow.

It will:
1. Deploy the QQ API Worker and Durable Object.
2. Store QQ_SESSION_SECRET as a Cloudflare Worker Secret.
3. Resolve the public HTTPS API address automatically.
4. Trigger "Build Folia iOS IPA (eSign)" with that address as VITE_QQ_API_BASE.

When the iOS workflow completes, download its Folia-iOS-unsigned artifact and sign it in eSign with your own certificate.

## Verify

After deployment, open:

https://folia-qq-api-ios.<your-workers.dev-subdomain>/api/qq/login/channels

The JSON response should list both qq and wechat in channels. If it lists only WeChat, check the Durable Object binding and migration.

## Security

- Never share the Cloudflare API Token or QQ_SESSION_SECRET.
- The Cloudflare Worker stores the session encryption key as a Worker Secret; the front end receives only the public API URL.
- The Durable Object holds the temporary MQTT WebSocket only while a QR login is active and releases it when the QR expires, login completes, or the user cancels.
