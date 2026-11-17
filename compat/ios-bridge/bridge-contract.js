/* Build-379 WebKit bridge contract helpers.
 * This module validates web-side envelopes. Native code must independently
 * validate every message; this module is not an authorization boundary.
 */
"use strict";
const PLAYER_COMMANDS = new Set(["load","play","pause","seek","volume","muted","status","upcoming","startup_prompts_seen"]);
const PROVIDER_ACTIONS = new Set(["appleMusicOpen","appleMusicClose","appleMusicLogout","appleMusicRequest","appleMusicStatus","fnmusicLogin","fnmusicLogout","fnmusicRequest","fnmusicStatus"]);
const APPLE_MUSIC_OPERATIONS = new Set(["search","catalogSong","catalogAlbum","catalogAlbumTracks","catalogArtist","catalogArtistSongs","catalogArtistAlbums","personalFm","playlists","playlistTracks","playlistTrackCount","librarySongs","libraryAlbums","libraryAlbumTracks","lyrics","likeSong","addPlaylistTracks"]);
function isRecord(value){return value!==null&&typeof value==="object"&&!Array.isArray(value);}
function fail(error){return{ok:false,error};}
function validHttpFileUrl(value){if(typeof value!=="string"||value.length>8192)return false;try{const u=new URL(value);return["https:","http:","file:"].includes(u.protocol)&&!u.username&&!u.password;}catch{return false;}}
function validatePlayerRequest(m){
 if(!isRecord(m)||!PLAYER_COMMANDS.has(m.cmd))return fail("unknown-player-command");
 if(m.cmd==="startup_prompts_seen")return{ok:true};
 if(typeof m.session!=="string"||!m.session||m.session.length>256)return fail("invalid-session");
 if(!Number.isSafeInteger(m.generation)||m.generation<0)return fail("invalid-generation");
 switch(m.cmd){
  case"load":
   if(!validHttpFileUrl(m.url))return fail("invalid-url");
   if(!Number.isFinite(m.position)||m.position<0)return fail("invalid-position");
   if(typeof m.autoplay!=="boolean")return fail("invalid-autoplay");
   if(m.track!==undefined&&m.track!==null&&!isRecord(m.track))return fail("invalid-track");
   if(m.upcoming!==undefined&&(!Array.isArray(m.upcoming)||m.upcoming.length>500))return fail("invalid-upcoming");
   if(m.previous!==undefined&&(!Array.isArray(m.previous)||m.previous.length>500))return fail("invalid-previous");
   break;
  case"seek":if(!Number.isFinite(m.position)||m.position<0)return fail("invalid-position");break;
  case"volume":if(!Number.isFinite(m.volume)||m.volume<0||m.volume>1)return fail("invalid-volume");break;
  case"muted":if(typeof m.muted!=="boolean")return fail("invalid-muted");break;
  case"pause":
   if(m.userIntent!==undefined&&typeof m.userIntent!=="boolean")return fail("invalid-user-intent");
   if(m.releaseIntent!==undefined&&typeof m.releaseIntent!=="boolean")return fail("invalid-release-intent");
   break;
  case"upcoming":
   if(typeof m.currentTrackKey!=="string"||m.currentTrackKey.length>512)return fail("invalid-track-key");
   if(!(m.track===null||isRecord(m.track)))return fail("invalid-track");
   if(!Array.isArray(m.upcoming)||m.upcoming.length>500)return fail("invalid-upcoming");
   if(!Array.isArray(m.previous)||m.previous.length>500)return fail("invalid-previous");
   break;
 }
 return{ok:true};
}
function validateProviderRequest(m){
 if(!isRecord(m)||typeof m.id!=="string"||!m.id||m.id.length>256)return fail("invalid-request-id");
 if(!PROVIDER_ACTIONS.has(m.action))return fail("unknown-provider-action");
 if(m.action==="appleMusicRequest"){
  if(!APPLE_MUSIC_OPERATIONS.has(m.operation))return fail("unsupported-apple-operation");
  if(!isRecord(m.params))return fail("invalid-params");
 }
 if(m.action==="fnmusicRequest"){
  if(typeof m.path!=="string"||m.path.length>1024||!m.path.startsWith("/music/api/v1/")||m.path.startsWith("//")||m.path.includes("\\")||/[?#\x00-\x1f]/.test(m.path)||m.path.split("/").some(p=>p==="."||p===".."))return fail("invalid-fnmusic-path");
  if(!["GET","POST"].includes(String(m.method).toUpperCase()))return fail("invalid-method");
  if(m.params!==undefined&&!isRecord(m.params))return fail("invalid-params");
  if(m.body!==undefined&&!isRecord(m.body)&&!Array.isArray(m.body))return fail("invalid-body");
 }
 return{ok:true};
}
function validateProviderReply(m){
 if(!isRecord(m)||typeof m.id!=="string"||!m.id||!isRecord(m.payload))return fail("invalid-reply");
 if(typeof m.payload.ok!=="boolean")return fail("invalid-reply-status");
 if(m.payload.ok&&!Object.prototype.hasOwnProperty.call(m.payload,"data"))return fail("missing-reply-data");
 if(!m.payload.ok&&(typeof m.payload.error!=="string"||!m.payload.error))return fail("missing-reply-error");
 return{ok:true};
}
module.exports={PLAYER_COMMANDS,PROVIDER_ACTIONS,APPLE_MUSIC_OPERATIONS,validatePlayerRequest,validateProviderRequest,validateProviderReply};
