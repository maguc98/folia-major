# Deploy the Folia QQ Music backend from the iOS build workflow

The iOS build workflow can optionally deploy an isolated `folia-qq-api-ios` Worker in your Cloudflare account, enable the `QqQrChannel` Durable Object, create and retain the backend session secret, resolve the account's `workers.dev` subdomain, verify that QQ and WeChat login channels are available, and build the IPA with the verified API URL.

Everything stays on the `ios/esign-ipa` branch. The workflow does not modify `main`, and it never writes the QQ session key to repository files or build artifacts.

## Add one GitHub Actions repository secret

In the `maguc98/folia-major` GitHub repository, open [Settings → Secrets and variables → Actions](https://github.com/maguc98/folia-major/settings/secrets/actions) and add this repository secret:

| Secret name | Value |
| --- | --- |
| `CLOUDFLARE_API_TOKEN` | A Cloudflare API Token with **Account → Workers Scripts → Edit** permission. |

Create the token here: https://dash.cloudflare.com/profile/api-tokens.

The Cloudflare Account ID is already configured in this repository's workflow as an account identifier. It is not an authentication credential. When reusing this workflow in another account, replace that value with the new account ID.

Your Cloudflare account must have a `workers.dev` subdomain enabled. The public Worker URL is generated automatically as `https://folia-qq-api-ios.<your-subdomain>.workers.dev`.

## Enable automatic backend deployment

In the same GitHub Settings → Secrets and variables → Actions page, open the **Variables** tab and add this repository variable:

| Variable name | Value |
| --- | --- |
| `DEPLOY_QQ_API` | `true` |

After the Cloudflare API Token and variable are saved, the next iOS workflow run on `ios/esign-ipa` will:

1. Validate that the Cloudflare API Token is present.
2. Deploy the standalone QQ API Worker with the `QqQrChannel` Durable Object binding and migration.
3. Check whether `QQ_SESSION_SECRET` already exists in Cloudflare Worker Secrets. If it does not, generate a random 32-byte key and store it directly as a Worker Secret. Existing keys are retained on later deploys.
4. Resolve the public HTTPS API address automatically.
5. Verify that both `qq` and `wechat` login channels are present.
6. Build the iOS IPA with the verified endpoint injected as `VITE_QQ_API_BASE`.

The session key is generated on the GitHub runner and sent directly to Cloudflare. It is not printed, committed, uploaded as an artifact, or stored as a GitHub Actions variable. Do not add it manually or send it in chat.

When the iOS workflow completes, download its `Folia-iOS-unsigned` artifact and sign it in eSign with your own certificate.

## Verify

After deployment, the workflow checks:

`https://folia-qq-api-ios.<your-workers.dev-subdomain>/api/qq/login/channels`

The JSON response must list both `qq` and `wechat` in `channels`. The IPA build is stopped if that check fails.

## Security

- Never share or commit the Cloudflare API Token.
- `QQ_SESSION_SECRET` remains in Cloudflare Worker Secrets and is reused across deploys; rotating it would invalidate existing session-derived Durable Object identities.
- The front end receives only the public API URL, never the session key.
- The Durable Object holds the temporary MQTT WebSocket only while a QR login is active and releases it when the QR expires, login completes, or the user cancels.
