"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { createAppleMusicProvider, OPERATIONS } = require("../compat/ios-bridge/apple-music-provider");

function fixture(responses = {}) {
  const calls = [];
  const mk = {
    isAuthorized: true,
    developerToken: "developer-token",
    musicUserToken: "user-token",
    api: { v3: { async music(path, query, options) {
      calls.push({ path, query, options });
      const key = path + ":" + (options?.fetchOptions?.method || "GET");
      return responses[key] || responses[path] || { status: 200, data: { data: [] } };
    } } },
    async authorize() { this.isAuthorized = true; },
    async unauthorize() { this.isAuthorized = false; }
  };
  const windowRef = {
    MusicKit: { getInstance: () => mk },
    crypto: globalThis.crypto,
    TextEncoder,
    setTimeout,
    clearTimeout
  };
  return { mk, windowRef, calls, dispatch: createAppleMusicProvider({ windowRef }).dispatch };
}

test("provider operation allowlist and bounded request validation", async () => {
  const { dispatch } = fixture();
  assert.equal(OPERATIONS.has("search"), true);
  assert.equal((await dispatch({ action: "appleMusicRequest", operation: "unknown" })).error, "unsupported");
  assert.equal((await dispatch({ action: "appleMusicRequest", operation: "search", params: { query: " " } })).error, "invalid-request");
  assert.equal((await dispatch({ action: "appleMusicRequest", operation: "catalogSong", params: { catalogId: "../x" } })).error, "invalid-request");
  assert.equal((await dispatch({ action: "appleMusicRequest", operation: "likeSong", params: { catalogId: "12", liked: "yes" } })).error, "invalid-request");
});

test("search maps Apple Music result records into bounded provider records", async () => {
  const response = {
    status: 200,
    data: { results: { songs: { data: [{
      id: "123", type: "songs",
      attributes: {
        name: "Track", artistName: "Artist", albumName: "Album",
        durationInMillis: 180000, isrc: "ISRC", playParams: { id: "play-id", kind: "song", catalogId: "123" },
        artwork: { url: "https://example.test/{w}/{h}" }
      },
      relationships: { artists: { data: [{ id: "a1", attributes: { name: "Artist" } }] } }
    }], next: "https://api.music.apple.com/v1/catalog/us/search?offset=26" } } }
  };
  const { dispatch } = fixture({ "v1/catalog/us/search": response });
  const result = await dispatch({ action: "appleMusicRequest", operation: "search", params: { query: "Track", limit: 25, offset: 0 } });
  assert.equal(result.ok, true);
  assert.equal(result.data.items[0].attributes.name, "Track");
  assert.equal(result.data.items[0].attributes.playbackAvailable, true);
  assert.equal(result.data.hasMore, true);
  assert.equal(result.data.nextOffset, 26);
});

test("catalog requests reject foreign next-page origins and oversized lyric payloads", async () => {
  const badPage = { status: 200, data: { results: { songs: { data: [{ id: "1", type: "songs", attributes: {} }], next: "https://evil.test/?offset=2" } } } };
  const f1 = fixture({ "v1/catalog/us/search": badPage });
  const bad = await f1.dispatch({ action: "appleMusicRequest", operation: "search", params: { query: "x" } });
  assert.equal(bad.error, "invalid-response");

  const lyrics = { status: 200, data: { data: [{ attributes: { ttml: "x".repeat(2 * 1024 * 1024 + 1) } }] } };
  const f2 = fixture({ "v1/catalog/us/songs/1/syllable-lyrics": lyrics });
  const large = await f2.dispatch({ action: "appleMusicRequest", operation: "lyrics", params: { songId: "1" } });
  assert.equal(large.error, "invalid-response");
});

test("favorite writes use the correct method and provider status hashes user identity", async () => {
  const f = fixture({
    "v1/me/favorites:POST": { status: 204, data: {} },
    "v1/me/storefront": { status: 200, data: { data: [{ id: "us" }] } },
    "v1/me/social-profile": { status: 200, data: { data: [{ id: "profile-id", attributes: { name: "Listener" } }] } }
  });
  const liked = await f.dispatch({ action: "appleMusicRequest", operation: "likeSong", params: { catalogId: "123", liked: true } });
  assert.equal(liked.ok, true);
  assert.equal(f.calls.some(call => call.path === "v1/me/favorites" && call.options.fetchOptions.method === "POST"), true);
  const status = await f.dispatch({ action: "appleMusicStatus" });
  assert.equal(status.ok, true);
  assert.equal(status.data.authenticated, true);
  assert.equal(status.data.user.nickname, "Listener");
  assert.equal(status.data.storefront, "us");
  assert.equal(status.data.id.length, 64);
});

test("authorization and logout update MusicKit authorization without leaking tokens", async () => {
  const f = fixture();
  f.mk.isAuthorized = false;
  const opened = await f.dispatch({ action: "appleMusicOpen" });
  assert.deepEqual(opened, { ok: true, data: { authorized: true } });
  const loggedOut = await f.dispatch({ action: "appleMusicLogout" });
  assert.deepEqual(loggedOut, { ok: true, data: {} });
  assert.equal(f.mk.isAuthorized, false);
  assert.equal(JSON.stringify(loggedOut).includes("user-token"), false);
});

test("Apple Music status matches original authenticated/user envelope", async () => {
  const f = fixture();
  f.mk.isAuthorized = false;
  const result = await f.dispatch({ action: "appleMusicStatus" });
  assert.deepEqual(result, { ok: true, data: { authenticated: false } });
});
