# Deploy the Folia QQ Music backend from the iOS build workflow

The iOS build workflow can optionally deploy an isolated folia-qq-api-ios Worker in your own Cloudflare account, enable the QqQrChannel Durable Object, upload QQ_SESSION_SECRET, resolve the account's workers.dev subdomain, verify that both QQ and WeChat login channels are available, and then build the IPA with the generated API URL.

It does not modify main and never writes the QQ session key to repository files or build artifacts.

## Add three GitHub Actions repository secrets

In the maguc98/folia-major GitHub repository, open Settings → Secrets and variables → Actions → New repository secret, then add:

| Secret name | Value |
| --- | --- |
| CLOUDFLARE_API_TOKEN | A Cloudflare API Token. Grant at least Account → Workers Scripts → Edit. This also permits reading the workers.dev subdomain. |
| CLOUDFLARE_ACCOUNT_ID | Your Cloudflare Account ID. |
| QQ_SESSION_SECRET | A random secret of at least 32 bytes. It is stored only in GitHub Secrets and Cloudflare Worker Secrets. |

Generate QQ_SESSION_SECRET locally with: openssl rand -base64 32. Do not send the generated value in chat, commit it to Git, or store it as a normal Actions Variable.

Create a Cloudflare API Token here: https://dash.cloudflare.com/profile/api-tokens. Your account must have a workers.dev subdomain enabled. The public Worker URL is generated automatically as folia-qq-api-ios.<your-subdomain>.workers.dev.

## Run deployment and build

After adding the three secrets, open the repository's Actions tab, select "Build Folia iOS IPA (eSign)", choose the ios/esign-ipa branch, and run the workflow.

In the workflow inputs:
- Enable "Deploy the QQ API to your Cloudflare account before building".
- Leave "External QQ Music API base URL" empty.

The workflow will:
1. Deploy the standalone QQ API Worker with the QqQrChannel Durable Object binding and migration.
2. Store QQ_SESSION_SECRET as a Cloudflare Worker Secret.
3. Resolve the public HTTPS API address automatically.
4. Call the login-channels endpoint and verify that both qq and wechat are present.
5. Build the iOS IPA with the verified endpoint injected as VITE_QQ_API_BASE.

When the iOS workflow completes, download its Folia-iOS-unsigned artifact and sign it in eSign with your own certificate.

## Verify

After deployment, the workflow checks:

https://folia-qq-api-ios.<your-workers.dev-subdomain>/api/qq/login/channels

The JSON response must list both qq and wechat in channels. The IPA build is stopped if that check fails.

## Security

- Never share the Cloudflare API Token or QQ_SESSION_SECRET.
- The Cloudflare Worker stores the session encryption key as a Worker Secret; the front end receives only the public API URL.
- The Durable Object holds the temporary MQTT WebSocket only while a QR login is active and releases it when the QR expires, login completes, or the user cancels.
