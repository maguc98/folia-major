/* Build-379 WebKit bridge contract helpers.
 * This module validates web-side envelopes. Native code must independently
 * validate every message; this module is not an authorization boundary.
 */
"use strict";

const PLAYER_COMMANDS = new Set([
  "load", "play", "pause", "seek", "volume", "muted", "status",
  "upcoming", "startup_prompts_seen"
]);
const PROVIDER_ACTIONS = new Set([
  "appleMusicOpen", "appleMusicClose", "appleMusicLogout",
  "appleMusicRequest", "appleMusicStatus", "fnmusicLogin",
  "fnmusicLogout", "fnmusicRequest", "fnmusicStatus"
]);
const APPLE_MUSIC_OPERATIONS = new Set([
  "search", "catalogSong", "catalogAlbum", "catalogAlbumTracks",
  "catalogArtist", "catalogArtistSongs", "catalogArtistAlbums",
  "personalFm", "playlists", "playlistTracks", "playlistTrackCount",
  "librarySongs", "libraryAlbums", "libraryAlbumTracks", "lyrics",
  "likeSong", "addPlaylistTracks"
]);

function isRecord(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function fail(reason) {
  return { ok: false, error: reason };
}
function validHttpFileUrl(value) {
  if (typeof value !== "string" || value.length > 8192) return false;
  try {
    const parsed = new URL(value);
    return ["https:", "http:", "file:"].includes(parsed.protocol)
      && !parsed.username && !parsed.password;
  } catch {
    return false;
  }
}

function validatePlayerRequest(message) {
  if (!isRecord(message) || !PLAYER_COMMANDS.has(message.cmd)) return fail("unknown-player-command");
  if (message.cmd === "startup_prompts_seen") return { ok: true };
  if (typeof message.session !== "string" || !message.session || message.session.length > 256) return fail("invalid-session");
  if (!Number.isSafeInteger(message.generation) || message.generation < 0) return fail("invalid-generation");

  switch (message.cmd) {
    case "load":
      if (!validHttpFileUrl(message.url)) return fail("invalid-url");
      if (!Number.isFinite(message.position) || message.position < 0) return fail("invalid-position");
      if (typeof message.autoplay !== "boolean") return fail("invalid-autoplay");
      if (message.track !== undefined && message.track !== null && !isRecord(message.track)) return fail("invalid-track");
      if (message.upcoming !== undefined && (!Array.isArray(message.upcoming) || message.upcoming.length > 500)) return fail("invalid-upcoming");
      if (message.previous !== undefined && (!Array.isArray(message.previous) || message.previous.length > 500)) return fail("invalid-previous");
      break;
    case "seek":
      if (!Number.isFinite(message.position) || message.position < 0) return fail("invalid-position");
      break;
    case "volume":
      if (!Number.isFinite(message.volume) || message.volume < 0 || message.volume > 1) return fail("invalid-volume");
      break;
    case "muted":
      if (typeof message.muted !== "boolean") return fail("invalid-muted");
      break;
    case "pause":
      if (message.userIntent !== undefined && typeof message.userIntent !== "boolean") return fail("invalid-user-intent");
      if (message.releaseIntent !== undefined && typeof message.releaseIntent !== "boolean") return fail("invalid-release-intent");
      break;
    case "upcoming":
      if (typeof message.currentTrackKey !== "string" || message.currentTrackKey.length > 512) return fail("invalid-track-key");
      if (!(message.track === null || isRecord(message.track))) return fail("invalid-track");
      if (!Array.isArray(message.upcoming) || message.upcoming.length > 500) return fail("invalid-upcoming");
      if (!Array.isArray(message.previous) || message.previous.length > 500) return fail("invalid-previous");
      break;
  }
  return { ok: true };
}

function validateProviderRequest(message) {
  if (!isRecord(message) || typeof message.id !== "string" || !message.id || message.id.length > 256) return fail("invalid-request-id");
  if (!PROVIDER_ACTIONS.has(message.action)) return fail("unknown-provider-action");

  if (message.action === "appleMusicRequest") {
    if (!APPLE_MUSIC_OPERATIONS.has(message.operation)) return fail("unsupported-apple-operation");
    if (!isRecord(message.params)) return fail("invalid-params");
  }
  if (message.action === "fnmusicRequest") {
    if (typeof message.path !== "string" || message.path.length > 1024
      || !message.path.startsWith("/music/api/v1/")
      || message.path.startsWith("//")
      || /[\\\\?#\\u0000-\\u001f]/.test(message.path)
      || message.path.split("/").some(part => part === "." || part === "..")) {
      return fail("invalid-fnmusic-path");
    }
    if (!["GET", "POST"].includes(String(message.method).toUpperCase())) return fail("invalid-method");
    if (message.params !== undefined && !isRecord(message.params)) return fail("invalid-params");
    if (message.body !== undefined && !isRecord(message.body) && !Array.isArray(message.body)) return fail("invalid-body");
  }
  // Login payloads are intentionally opaque here; the native side must validate
  // their exact shape and never log credentials.
  return { ok: true };
}

function validateProviderReply(message) {
  if (!isRecord(message) || typeof message.id !== "string" || !message.id || !isRecord(message.payload)) return fail("invalid-reply");
  if (typeof message.payload.ok !== "boolean") return fail("invalid-reply-status");
  if (message.payload.ok && !Object.prototype.hasOwnProperty.call(message.payload, "data")) return fail("missing-reply-data");
  if (!message.payload.ok && (typeof message.payload.error !== "string" || !message.payload.error)) return fail("missing-reply-error");
  return { ok: true };
}

module.exports = {
  PLAYER_COMMANDS,
  PROVIDER_ACTIONS,
  APPLE_MUSIC_OPERATIONS,
  validatePlayerRequest,
  validateProviderRequest,
  validateProviderReply
};
