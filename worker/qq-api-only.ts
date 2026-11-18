import { Buffer } from 'buffer';
import { QQ_API_PREFIX, handleQq, type QqServerlessEnv } from './qq.ts';

// The QQ API package uses Node Buffer semantics for MQTT frames. Keep the same
// Workers-compatible Buffer shim used by worker/index.ts.
(globalThis as typeof globalThis & { Buffer: typeof Buffer }).Buffer = Buffer;

// Exporting the class is required for the Durable Object binding in wrangler.qq-api.jsonc.
export { QqQrChannel } from './qqQrChannel.ts';

export default {
  async fetch(request: Request, env: QqServerlessEnv): Promise<Response> {
    const { pathname } = new URL(request.url);
    if (pathname !== QQ_API_PREFIX && !pathname.startsWith(QQ_API_PREFIX + '/')) {
      return new Response('Not Found', { status: 404 });
    }

    try {
      return await handleQq(request, env);
    } catch {
      // Never echo exception details: request errors may contain authentication material.
      console.error('[qq-api-worker] request failed');
      return new Response(
        JSON.stringify({ code: 502, message: 'QQ API request failed' }),
        { status: 502, headers: { 'content-type': 'application/json; charset=utf-8' } },
      );
    }
  },
};
