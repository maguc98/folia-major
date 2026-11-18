# Deploy the Folia QQ Music backend from the iOS build workflow

The iOS build workflow can optionally deploy an isolated folia-qq-api-ios Worker in your own Cloudflare account, enable the QqQrChannel Durable Object, upload QQ_SESSION_SECRET, resolve the account's workers.dev subdomain, verify that both QQ and WeChat login channels are available, and build the IPA with the generated API URL.

Everything stays on the ios/esign-ipa branch. The workflow does not modify main and never writes the QQ session key to repository files or build artifacts.

## Add three GitHub Actions repository secrets

In the maguc98/folia-major GitHub repository, open Settings → Secrets and variables → Actions → New repository secret, then add:

| Secret name | Value |
| --- | --- |
| CLOUDFLARE_API_TOKEN | A Cloudflare API Token. Grant at least Account → Workers Scripts → Edit. This also permits reading the workers.dev subdomain. |
| CLOUDFLARE_ACCOUNT_ID | Your Cloudflare Account ID. |
| QQ_SESSION_SECRET | A random secret of at least 32 bytes. It is stored only in GitHub Secrets and Cloudflare Worker Secrets. |

Generate QQ_SESSION_SECRET locally with: openssl rand -base64 32. Do not send the generated value in chat, commit it to Git, or store it as a normal Actions Variable.

Create a Cloudflare API Token here: https://dash.cloudflare.com/profile/api-tokens. Your account must have a workers.dev subdomain enabled. The public Worker URL is generated automatically as folia-qq-api-ios.<your-subdomain>.workers.dev.

## Enable automatic backend deployment

In the same GitHub Settings → Secrets and variables → Actions page, open the Variables tab and add this repository variable:

| Variable name | Value |
| --- | --- |
| DEPLOY_QQ_API | true |

After the three secrets and this variable are saved, the next iOS workflow run on ios/esign-ipa will:
1. Validate that all three secrets exist.
2. Deploy the standalone QQ API Worker with the QqQrChannel Durable Object binding and migration.
3. Store QQ_SESSION_SECRET as a Cloudflare Worker Secret and republish the Worker.
4. Resolve the public HTTPS API address automatically.
5. Verify that both qq and wechat login channels are present.
6. Build the iOS IPA with the verified endpoint injected as VITE_QQ_API_BASE.

The branch already has the workflow changes. After the secrets and variable are ready, the next push that triggers the iOS workflow will deploy the backend and build the IPA. You can ask me to trigger that build; do not send the secret values in chat.

When the iOS workflow completes, download its Folia-iOS-unsigned artifact and sign it in eSign with your own certificate.

## Verify

After deployment, the workflow checks:

https://folia-qq-api-ios.<your-workers.dev-subdomain>/api/qq/login/channels

The JSON response must list both qq and wechat in channels. The IPA build is stopped if that check fails.

## Security

- Never share the Cloudflare API Token or QQ_SESSION_SECRET.
- The Cloudflare Worker stores the session encryption key as a Worker Secret; the front end receives only the public API URL.
- The Durable Object holds the temporary MQTT WebSocket only while a QR login is active and releases it when the QR expires, login completes, or the user cancels.
