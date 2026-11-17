const test = require("node:test");
const assert = require("node:assert/strict");
const {
  validatePlayerRequest,
  validateProviderRequest,
  validateProviderReply
} = require("../compat/ios-bridge/bridge-contract");
const { createPlayerTransport, createProviderTransport } = require("../compat/ios-bridge/bridge-client");

test("player transport stamps session and generation", () => {
  const sent = [];
  const player = createPlayerTransport({ postMessage: m => sent.push(m), session: "s1", generation: 2 });
  player.send("seek", { position: 8 });
  assert.deepEqual(sent[0], { cmd: "seek", position: 8, generation: 2, session: "s1" });
  assert.equal(player.nextGeneration(), 3);
});

test("player rejects invalid volume and unsafe URL", () => {
  assert.equal(validatePlayerRequest({cmd:"volume",volume:2,session:"s",generation:0}).ok, false);
  assert.equal(validatePlayerRequest({cmd:"load",url:"javascript:alert(1)",position:0,autoplay:true,session:"s",generation:0}).ok, false);
});

test("provider validator rejects arbitrary actions and path traversal", () => {
  assert.equal(validateProviderRequest({id:"x",action:"arbitrary"}).ok, false);
  assert.equal(validateProviderRequest({id:"x",action:"fnmusicRequest",path:"/music/api/v1/../../secret",method:"GET"}).ok, false);
});

test("provider reply envelope requires data or error", () => {
  assert.equal(validateProviderReply({id:"x",payload:{ok:true}}).ok, false);
  assert.equal(validateProviderReply({id:"x",payload:{ok:false,error:"denied"}}).ok, true);
});

test("provider transport resolves a correlated reply exactly once", async () => {
  let outbound;
  const provider = createProviderTransport({postMessage:m => { outbound=m; }, idFactory:()=>"fixed-id", timeoutMs:1000});
  const result = provider.request("appleMusicRequest", {operation:"lyrics",params:{id:"123"}});
  assert.equal(provider.pendingCount, 1);
  assert.equal(provider.receive({id:outbound.id,payload:{ok:true,data:{lyrics:[]}}}), true);
  assert.deepEqual(await result, {lyrics:[]});
  assert.equal(provider.pendingCount, 0);
  assert.equal(provider.receive({id:outbound.id,payload:{ok:true,data:{}}}), false);
});

test("provider transport clears pending requests on close", async () => {
  const provider = createProviderTransport({postMessage:()=>{}, idFactory:()=>"closing", timeoutMs:10000});
  const pending = provider.request("appleMusicStatus");
  provider.close("webview-gone");
  await assert.rejects(pending, /webview-gone/);
  assert.equal(provider.pendingCount, 0);
});
