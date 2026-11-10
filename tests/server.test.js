"use strict";
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { createServer } = require("../gitops/app/server.js");

async function withServer(config, fn) {
  const server = createServer(config);
  await new Promise(resolve => server.listen(0,"127.0.0.1",resolve));
  try { return await fn(`http://127.0.0.1:${server.address().port}`); }
  finally { await new Promise((resolve,reject)=>server.close(err=>err?reject(err):resolve())); }
}

test("liveness responds with status 200", async()=>{
  await withServer({},async base=>{const res=await fetch(base+"/health/live");assert.equal(res.status,200);assert.equal((await res.json()).status,"live");});
});
test("readiness responds 200 in healthy mode", async()=>{
  await withServer({readyMode:"ok"},async base=>{const res=await fetch(base+"/health/ready");assert.equal(res.status,200);});
});
test("readiness can fail without killing the process", async()=>{
  await withServer({readyMode:"fail"},async base=>{const r=await fetch(base+"/health/ready");assert.equal(r.status,503);const live=await fetch(base+"/health/live");assert.equal(live.status,200);});
});
test("stations API returns three stations",async()=>{
  await withServer({},async base=>{const r=await fetch(base+"/api/stations");assert.equal(r.status,200);assert.equal((await r.json()).stations.length,3);});
});
test("homepage identifies release",async()=>{
  await withServer({release:"v1"},async base=>{const r=await fetch(base);assert.equal(r.status,200);assert.match(await r.text(),/Release: v1/);});
});
