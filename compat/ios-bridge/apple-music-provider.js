"use strict";

const OPERATIONS = new Set([
  "search", "catalogSong", "catalogAlbum", "catalogAlbumTracks",
  "catalogArtist", "catalogArtistSongs", "catalogArtistAlbums",
  "personalFm", "playlists", "playlistTracks", "playlistTrackCount",
  "librarySongs", "libraryAlbums", "libraryAlbumTracks", "lyrics",
  "likeSong", "addPlaylistTracks"
]);
const ID = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const NUMERIC_ID = /^[0-9]{1,40}$/;
const PLAYLIST_ID = /^p\.[A-Za-z0-9._-]{1,198}$/;

function createAppleMusicProvider({ windowRef, fetchImpl } = {}) {
  if (!windowRef) throw new Error("window-required");
  const fetcher = fetchImpl || windowRef.fetch?.bind(windowRef);
  const clampInt = (value, fallback, max) => {
    const n = Number(value);
    return Number.isFinite(n) ? Math.max(0, Math.min(max, Math.floor(n))) : fallback;
  };
  const safeString = value => typeof value === "string" ? value.slice(0, 4096) : "";
  const error = code => ({ ok: false, error: code });

  function apiFor(mk) {
    const modern = mk.api?.v3;
    const legacy = mk.api;
    const direct = fetcher && typeof mk.developerToken === "string" && mk.developerToken &&
      typeof mk.musicUserToken === "string" && mk.musicUserToken
      ? async (path, query = {}, options = {}) => {
          const url = new URL(path, "https://api.music.apple.com");
          for (const [key, value] of Object.entries({ ...query, ...options })) {
            if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
          }
          const response = await fetcher(url, {
            headers: {
              Authorization: "Bearer " + mk.developerToken,
              "Music-User-Token": mk.musicUserToken
            }
          });
          let data = null;
          try { data = await response.json(); } catch {}
          return { status: response.status, data };
        }
      : null;

    const call = typeof modern?.music === "function" ? modern.music.bind(modern)
      : typeof legacy?.music === "function"
        ? (path, query, options) => options
          ? legacy.music(path, query, options.fetchOptions)
          : legacy.music(path, query)
        : direct;

    const write = typeof modern?.music === "function"
      ? async (path, query, method, body) => modern.music(path, query, {
          fetchOptions: {
            method,
            ...(body === undefined ? {} : {
              body: JSON.stringify(body),
              headers: { "Content-Type": "application/json" }
            })
          }
        })
      : typeof legacy?.music === "function"
        ? async (path, query, method, body) => legacy.music(path, query, {
            method,
            ...(body === undefined ? {} : { body: JSON.stringify(body) }),
            ...(body === undefined ? {} : { headers: { "Content-Type": "application/json" } })
          })
        : direct
          ? async (path, query, method, body) => {
              const url = new URL(path, "https://api.music.apple.com");
              for (const [key, value] of Object.entries(query || {})) {
                if (value !== undefined && value !== null) url.searchParams.set(key, String(value));
              }
              const response = await fetcher(url, {
                method,
                headers: {
                  Authorization: "Bearer " + mk.developerToken,
                  "Music-User-Token": mk.musicUserToken,
                  ...(body === undefined ? {} : { "Content-Type": "application/json" })
                },
                ...(body === undefined ? {} : { body: JSON.stringify(body) })
              });
              let data = null;
              try { data = await response.json(); } catch {}
              return { status: response.status, data };
            }
          : null;
    return { call, write };
  }

  const succeeded = result =>
    Number.isInteger(Number(result?.status)) &&
    Number(result.status) >= 200 && Number(result.status) < 300 &&
    !result?.data?.errors?.length && !result?.errors?.length;

  const writeFailure = result => {
    const status = Number(result?.status);
    return error(status === 401 || status === 403 ? "auth-required" : "upstream-error");
  };

  async function status(mk, call) {
    const account = await call("v1/me/storefront");
    const store = account?.data?.data?.[0]?.id;
    if (typeof store !== "string" || !/^[a-z]{2}$/.test(store)) {
      const statusCode = Number(account?.status);
      return error(statusCode === 401 || statusCode === 403 ? "auth-required" : "storefront-unavailable");
    }
    windowRef.__foliaStorefront = account;

    const profile = await Promise.race([
      Promise.resolve().then(() => call("v1/me/social-profile")).catch(() => null),
      new Promise(resolve => windowRef.setTimeout(() => resolve(null), 1500))
    ]);
    const item = profile?.data?.data?.[0];
    let identity = typeof item?.id === "string" ? item.id : "";
    if (!identity && typeof mk.musicUserToken === "string" && mk.musicUserToken) {
      identity = "music-user-token:" + mk.musicUserToken;
    }
    if (!identity || !windowRef.crypto?.subtle || !windowRef.TextEncoder) {
      return error("identity-unavailable");
    }
    const bytes = new windowRef.TextEncoder().encode("folia-apple-music:" + identity);
    const digest = await windowRef.crypto.subtle.digest("SHA-256", bytes);
    const id = Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
    let avatarUrl = "";
    const artwork = item?.attributes?.artwork?.url;
    if (typeof artwork === "string") {
      try {
        const url = new URL(artwork.replaceAll("{w}", "128").replaceAll("{h}", "128"));
        if (url.protocol === "https:" && !url.username && !url.password) avatarUrl = url.toString();
      } catch {}
    }
    return { ok: true, data: {
      id,
      nickname: typeof item?.attributes?.name === "string" ? item.attributes.name.slice(0, 256) : "Apple Music",
      avatarUrl,
      storefront: store
    } };
  }

  async function requestOperation(mk, call, write, operation, rawParams) {
    const params = rawParams && typeof rawParams === "object" && !Array.isArray(rawParams) ? { ...rawParams } : {};
    if (!OPERATIONS.has(operation)) return error("unsupported");

    if (operation === "likeSong" || operation === "addPlaylistTracks") {
      if (typeof write !== "function") return error("not-ready");
      if (operation === "likeSong") {
        if (typeof params.catalogId !== "string" || !NUMERIC_ID.test(params.catalogId) ||
            typeof params.liked !== "boolean") return error("invalid-request");
        const result = await write("v1/me/favorites", { "ids[songs]": params.catalogId },
          params.liked ? "POST" : "DELETE");
        return succeeded(result) ? { ok: true, data: {} } : writeFailure(result);
      }
      if (typeof params.playlistId !== "string" || !PLAYLIST_ID.test(params.playlistId) ||
          !Array.isArray(params.catalogIds) || params.catalogIds.length < 1 ||
          params.catalogIds.length > 100 ||
          params.catalogIds.some(id => typeof id !== "string" || !NUMERIC_ID.test(id))) {
        return error("invalid-request");
      }
      const catalogIds = [...new Set(params.catalogIds)];
      const playlistPath = "v1/me/library/playlists/" + encodeURIComponent(params.playlistId);
      const detail = await call(playlistPath, { extend: "tags" });
      if (!succeeded(detail)) return writeFailure(detail);
      const playlist = detail?.data?.data?.find(item =>
        item.id === params.playlistId && item.type === "library-playlists");
      if (!playlist) return error("invalid-response");
      if (playlist.attributes?.canEdit !== true || playlist.attributes?.tags?.includes("favorited")) {
        return error("unsupported");
      }
      const result = await write(playlistPath + "/tracks", { representation: "resources" }, "POST", {
        data: catalogIds.map(id => ({ id, type: "songs" }))
      });
      return succeeded(result) ? { ok: true, data: {} } : writeFailure(result);
    }

    const account = await call("v1/me/storefront");
    const store = account?.data?.data?.[0]?.id;
    if (typeof store !== "string" || !/^[a-z]{2}$/.test(store)) {
      const statusCode = Number(account?.status);
      return error(statusCode === 401 || statusCode === 403 ? "auth-required" : "storefront-unavailable");
    }
    windowRef.__foliaStorefront = account;
    const limit = Math.max(1, Math.min(100, clampInt(params.limit, 25, 100)));
    const offset = clampInt(params.offset, 0, 100000);
    const base = "v1/catalog/" + store;
    let path = "";
    let options = {};
    let personalFmResult = null;

    if (operation === "search") {
      if (typeof params.query !== "string" || !params.query.trim() || params.query.length > 200) {
        return error("invalid-request");
      }
      path = base + "/search";
      options = { term: params.query.trim(), types: "songs", limit, offset };
    } else if (["catalogSong", "catalogAlbum", "catalogAlbumTracks", "catalogArtist",
      "catalogArtistSongs", "catalogArtistAlbums"].includes(operation)) {
      if (typeof params.catalogId !== "string" || !NUMERIC_ID.test(params.catalogId)) {
        return error("invalid-request");
      }
      const paths = {
        catalogSong: "/songs/", catalogAlbum: "/albums/", catalogAlbumTracks: "/albums/",
        catalogArtist: "/artists/", catalogArtistSongs: "/artists/", catalogArtistAlbums: "/artists/"
      };
      const suffixes = {
        catalogAlbumTracks: "/tracks", catalogArtistSongs: "/view/top-songs",
        catalogArtistAlbums: "/albums"
      };
      path = base + paths[operation] + encodeURIComponent(params.catalogId) + (suffixes[operation] || "");
      options = ["catalogSong", "catalogAlbum", "catalogArtist"].includes(operation)
        ? {} : { limit, offset };
    } else if (operation === "personalFm") {
      const stations = await call(base + "/stations", { "filter[identity]": "personal", limit: 1 });
      const stationStatus = Number(stations?.status) || 0;
      if (stationStatus >= 400 || stations?.data?.errors?.length) {
        personalFmResult = stations;
      } else {
        const rows = stations?.data?.data;
        const station = Array.isArray(rows) && rows.length === 1 && rows[0]?.type === "stations" &&
          typeof rows[0]?.id === "string" && /^ra\.[A-Za-z0-9._-]{1,196}$/.test(rows[0].id)
          ? rows[0] : null;
        personalFmResult = station
          ? await write("v1/me/stations/next-tracks/" + encodeURIComponent(station.id), { limit: 2 }, "POST")
          : { status: 502, data: { errors: [{}] } };
      }
    } else if (operation === "playlists") {
      path = "v1/me/library/playlists";
      options = { limit, offset, extend: "tags" };
    } else if (operation === "playlistTracks" || operation === "playlistTrackCount") {
      if (typeof params.playlistId !== "string" || !ID.test(params.playlistId)) return error("invalid-request");
      path = "v1/me/library/playlists/" + encodeURIComponent(params.playlistId) + "/tracks";
      options = operation === "playlistTrackCount"
        ? { limit: 1 } : { limit, offset, include: "catalog" };
    } else if (operation === "librarySongs") {
      path = "v1/me/library/songs";
      options = { limit, offset, include: "catalog" };
    } else if (operation === "libraryAlbums") {
      path = "v1/me/library/albums";
      options = { limit, offset };
    } else if (operation === "libraryAlbumTracks") {
      if (typeof params.albumId !== "string" || !ID.test(params.albumId)) return error("invalid-request");
      path = "v1/me/library/albums/" + encodeURIComponent(params.albumId) + "/tracks";
      options = { limit, offset, include: "catalog" };
    } else if (operation === "lyrics") {
      let lyricId = typeof params.songId === "string" && NUMERIC_ID.test(params.songId) ? params.songId : "";
      const libraryId = typeof params.librarySongId === "string" && ID.test(params.librarySongId)
        ? params.librarySongId : "";
      if (!lyricId && libraryId) {
        const relation = await call("v1/me/library/songs/" + encodeURIComponent(libraryId), { include: "catalog" });
        const relationStatus = Number(relation?.status) || 0;
        if (relationStatus === 401 || relationStatus === 403) return error("auth-required");
        if (relationStatus >= 400 || relation?.data?.errors?.length) return { ok: true, data: { ttml: null } };
        const resource = relation?.data?.data?.[0];
        const relatedId = resource?.attributes?.playParams?.catalogId ||
          resource?.relationships?.catalog?.data?.[0]?.id;
        const candidate = String(relatedId || "");
        if (!NUMERIC_ID.test(candidate)) return { ok: true, data: { ttml: null } };
        lyricId = candidate;
      }
      if (!NUMERIC_ID.test(lyricId)) return error("invalid-request");
      params.songId = lyricId;
      path = base + "/songs/" + encodeURIComponent(lyricId) + "/syllable-lyrics";
    } else {
      return error("unsupported");
    }

    let result = personalFmResult === null ? await call(path, options) : personalFmResult;
    let statusCode = Number(result?.status) || 0;
    if (operation === "lyrics" && statusCode === 404) {
      const originalId = params.songId;
      const equivalentResult = await call(base + "/songs", { "filter[equivalents]": originalId });
      const equivalentStatus = Number(equivalentResult?.status) || 0;
      if (equivalentStatus === 401 || equivalentStatus === 403) return error("auth-required");
      if (equivalentStatus >= 400 || equivalentResult?.data?.errors?.length) {
        return { ok: true, data: { ttml: null } };
      }
      const matches = equivalentResult?.data?.meta?.filters?.equivalents?.[originalId];
      const replacement = Array.isArray(matches)
        ? String(matches.find(item => item?.type === "songs" && NUMERIC_ID.test(String(item.id)) &&
          String(item.id) !== originalId)?.id || "") : "";
      if (!replacement) return { ok: true, data: { ttml: null } };
      result = await call(base + "/songs/" + encodeURIComponent(replacement) + "/syllable-lyrics", options);
      statusCode = Number(result?.status) || 0;
    }
    if (statusCode >= 400 || result?.data?.errors?.length) {
      return error(statusCode === 401 || statusCode === 403 ? "auth-required" : "upstream-error");
    }
    if (operation === "lyrics") {
      const ttml = result?.data?.data?.[0]?.attributes?.ttml;
      if (typeof ttml !== "string") return { ok: true, data: { ttml: null } };
      if (ttml.length > 2 * 1024 * 1024) return error("invalid-response");
      return { ok: true, data: { ttml } };
    }
    if (operation === "playlistTrackCount") {
      const total = result?.data?.meta?.total;
      return { ok: true, data: { total: Number.isSafeInteger(total) && total >= 0 ? total : null } };
    }

    const results = result?.data?.results;
    const page = operation === "search"
      ? (results == null || (typeof results === "object" && !Array.isArray(results) &&
        results.songs === undefined) ? { data: [] } : results?.songs)
      : result?.data;
    if (!Array.isArray(page?.data) || page.data.length > limit) return error("invalid-response");
    const items = page.data.map(item => {
      const attributes = item?.attributes || {};
      const play = attributes.playParams || {};
      const artwork = safeString(attributes.artwork?.url);
      return {
        id: safeString(item?.id),
        type: safeString(item?.type),
        attributes: {
          playbackAvailable: typeof play.id === "string" && play.id.length > 0,
          ...(typeof attributes.canEdit === "boolean" ? { canEdit: attributes.canEdit } : {}),
          isLive: attributes.isLive === true,
          isFavoritePlaylist: Array.isArray(attributes.tags) && attributes.tags.includes("favorited"),
          name: safeString(attributes.name),
          artistName: safeString(attributes.artistName),
          albumName: safeString(attributes.albumName),
          durationInMillis: Number.isFinite(attributes.durationInMillis) ? attributes.durationInMillis : 0,
          trackCount: Number.isSafeInteger(attributes.trackCount) && attributes.trackCount >= 0
            ? attributes.trackCount : null,
          artwork: { url: artwork },
          isrc: safeString(attributes.isrc),
          catalogAlbums: (Array.isArray(item?.relationships?.albums?.data) ? item.relationships.albums.data : [])
            .slice(0, 10).map(entry => ({ id: safeString(entry?.id), name: safeString(entry?.attributes?.name) })),
          catalogArtists: (Array.isArray(item?.relationships?.artists?.data) ? item.relationships.artists.data : [])
            .slice(0, 10).map(entry => ({ id: safeString(entry?.id), name: safeString(entry?.attributes?.name) })),
          playParams: {
            id: safeString(play.id),
            kind: safeString(play.kind),
            catalogId: safeString(play.catalogId || item?.relationships?.catalog?.data?.[0]?.id),
            isLibrary: play.isLibrary === true
          }
        }
      };
    });
    const hasMore = typeof page.next === "string" && page.next.length > 0;
    if (hasMore && items.length === 0) return error("invalid-response");
    let nextOffset = offset + items.length;
    if (hasMore) {
      const next = new URL(page.next, "https://api.music.apple.com");
      if (next.origin !== "https://api.music.apple.com") return error("invalid-response");
      const text = next.searchParams.get("offset");
      const suppliedOffset = text && /^[0-9]+$/.test(text) ? Number(text) : NaN;
      if (!Number.isSafeInteger(suppliedOffset) || suppliedOffset < offset + items.length ||
          suppliedOffset <= offset || suppliedOffset > 100000) return error("invalid-response");
      nextOffset = suppliedOffset;
    }
    return { ok: true, data: { items, hasMore, nextOffset } };
  }

  async function dispatch(request) {
    try {
      if (!request || typeof request !== "object" || Array.isArray(request) ||
          typeof request.action !== "string") return error("invalid-request");
      const mk = windowRef.MusicKit?.getInstance?.();
      if (!mk) return error("not-ready");

      if (request.action === "appleMusicOpen") {
        if (mk.isAuthorized === true) return { ok: true, data: { authorized: true } };
        if (typeof mk.authorize !== "function") return error("unsupported");
        await mk.authorize();
        return { ok: true, data: { authorized: mk.isAuthorized === true } };
      }
      if (request.action === "appleMusicClose") return error("unsupported");
      if (request.action === "appleMusicLogout") {
        if (typeof mk.unauthorize !== "function") return error("unsupported");
        await mk.unauthorize();
        windowRef.__foliaStorefront = null;
        windowRef.__foliaStorefrontAligned = false;
        windowRef.__foliaSubscribed = null;
        return { ok: true, data: {} };
      }

      const { call, write } = apiFor(mk);
      if (typeof call !== "function") return error("not-ready");
      if (request.action === "appleMusicStatus") return await status(mk, call);
      if (request.action === "appleMusicRequest") {
        return await requestOperation(mk, call, write, request.operation, request.params);
      }
      return error("unsupported-provider-action");
    } catch (cause) {
      const code = String(cause?.code || cause?.name || "request-failed")
        .replace(/[^A-Za-z0-9_.-]/g, "").slice(0, 80);
      return { ok: false, error: "request-failed", errorCode: code };
    }
  }

  return { dispatch };
}

function installAppleMusicProvider(windowRef, options = {}) {
  const service = createAppleMusicProvider({ ...options, windowRef });
  windowRef.__foliaAppleMusicProviderDispatch = request => service.dispatch(request);
  return service;
}

if (typeof window !== "undefined") {
  try { installAppleMusicProvider(window); } catch {}
}
if (typeof module !== "undefined" && module.exports) {
  module.exports = { OPERATIONS, createAppleMusicProvider, installAppleMusicProvider };
}
