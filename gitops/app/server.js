"use strict";
// CityBike service for the Kubernetes and GitOps lab.
// No third-party Node dependencies are required.
const http = require("node:http");

function createServer({ readyMode = process.env.READY_MODE || "ok", release = process.env.APP_RELEASE || "v1" } = {}) {
  const stations = [
    { id: "central", name: "Central Square", bikes: 9 },
    { id: "riverside", name: "Riverside Park", bikes: 0 },
    { id: "campus", name: "University Campus", bikes: 6 }
  ];
  return http.createServer((req, res) => {
    const route = new URL(req.url || "/", "http://localhost").pathname;
    function respond(code, body, contentType="application/json") {
      res.writeHead(code, {"content-type": contentType, "cache-control": "no-store"});
      res.end(contentType === "application/json" ? JSON.stringify(body) : body);
    }
    if (req.method !== "GET") return respond(405,{error:"method_not_allowed"});
    if (route === "/health/live") return respond(200,{status:"live",release});
    if (route === "/health/ready") return readyMode === "fail"
      ? respond(503,{status:"unready",reason:"simulated_dependency_failure",release})
      : respond(200,{status:"ready",release});
    if (route === "/api/stations") return respond(200,{stations,release});
    if (route === "/") return respond(200,`<!doctype html><html lang="en"><head><meta charset="utf-8"><title>CityBike GitOps</title></head><body><main><h1>CityBike Mobility</h1><p>Release: ${release}</p><p>Observe the platform, not just the code.</p></main></body></html>`,"text/html; charset=utf-8");
    return respond(404,{error:"not_found"});
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT || 3000);
  createServer().listen(port,"0.0.0.0",()=>console.log(`CityBike listening on ${port}`));
}
module.exports = {createServer};
