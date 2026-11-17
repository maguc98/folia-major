/* Small, injectable transports for the build-379 bridge contract.
 * Host app supplies postMessage; this module does not emulate native services.
 */
"use strict";

const {
  validatePlayerRequest,
  validateProviderRequest,
  validateProviderReply
} = require("./bridge-contract");

function createPlayerTransport(options) {
  const postMessage = options && options.postMessage;
  if (typeof postMessage !== "function") throw new TypeError("postMessage is required");
  let session = options.session;
  let generation = Number.isSafeInteger(options.generation) ? options.generation : 0;
  if (typeof session !== "string" || !session) throw new TypeError("non-empty session is required");

  return Object.freeze({
    get session() { return session; },
    get generation() { return generation; },
    nextGeneration() { generation += 1; return generation; },
    send(cmd, payload = {}) {
      const message = { ...payload, cmd, generation, session };
      const checked = validatePlayerRequest(message);
      if (!checked.ok) throw new TypeError(checked.error);
      postMessage(message);
      return message;
    }
  });
}

function createProviderTransport(options) {
  const postMessage = options && options.postMessage;
  if (typeof postMessage !== "function") throw new TypeError("postMessage is required");
  const timeoutMs = Number.isFinite(options.timeoutMs) ? options.timeoutMs : 45000;
  const idFactory = options.idFactory || (() => "provider-" + Date.now() + "-" + (++sequence));
  const pending = new Map();
  let sequence = 0;
  let closed = false;

  function cleanup(id) {
    const entry = pending.get(id);
    if (!entry) return null;
    clearTimeout(entry.timer);
    pending.delete(id);
    return entry;
  }

  return Object.freeze({
    request(action, payload = {}, requestTimeout = timeoutMs) {
      if (closed) return Promise.reject(new Error("bridge-closed"));
      const id = idFactory();
      const message = { ...payload, id, action };
      const checked = validateProviderRequest(message);
      if (!checked.ok) return Promise.reject(new TypeError(checked.error));
      if (pending.has(id)) return Promise.reject(new Error("duplicate-request-id"));

      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          cleanup(id);
          reject(new Error("provider-request-timeout"));
        }, requestTimeout);
        pending.set(id, { resolve, reject, timer });
        try {
          postMessage(message);
        } catch (error) {
          cleanup(id);
          reject(error);
        }
      });
    },

    receive(reply) {
      const checked = validateProviderReply(reply);
      if (!checked.ok) return false;
      const entry = cleanup(reply.id);
      if (!entry) return false;
      if (reply.payload.ok) entry.resolve(reply.payload.data);
      else entry.reject(new Error(reply.payload.error));
      return true;
    },

    close(reason = "bridge-closed") {
      closed = true;
      for (const [id] of pending) {
        const entry = cleanup(id);
        if (entry) entry.reject(new Error(reason));
      }
    },

    get pendingCount() { return pending.size; }
  });
}

module.exports = { createPlayerTransport, createProviderTransport };
