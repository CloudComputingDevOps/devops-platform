/**
 * Prueba de carga k6 contra el Gateway (vía Ingress o port-forward).
 *
 * Ejemplos:
 *   k6 run -e BASE_URL=http://gateway.local scripts/load/gateway-k6.js
 *   k6 run -e BASE_URL=http://127.0.0.1:3000 -e PATH=/ scripts/load/gateway-k6.js
 *
 * Umbrales pensados para evidencia: no fallan el job si el servicio
 * responde 404 en "/", solo miden disponibilidad TCP/HTTP.
 */
import http from "k6/http";
import { check, sleep } from "k6";
import { Rate, Trend } from "k6/metrics";

const errorRate = new Rate("errors");
const latency = new Trend("gateway_latency_ms");

const BASE_URL = __ENV.BASE_URL || "http://gateway.local";
const REQUEST_PATH = __ENV.REQUEST_PATH || "/api/areas";
const VUS = Number(__ENV.VUS || 10);
const DURATION = __ENV.DURATION || "60s";

export const options = {
  scenarios: {
    steady: {
      executor: "constant-vus",
      vus: VUS,
      duration: DURATION,
    },
  },
  thresholds: {
    http_req_failed: ["rate<0.5"],
    http_req_duration: ["p(95)<2000"],
  },
};

export default function () {
  const res = http.get(`${BASE_URL}${REQUEST_PATH}`, {
    tags: { endpoint: REQUEST_PATH },
    timeout: "10s",
  });

  latency.add(res.timings.duration);
  const ok = check(res, {
    "status is not 5xx": (r) => r.status < 500,
    "got a response": (r) => r.status !== 0,
  });
  errorRate.add(!ok);
  sleep(0.3);
}

export function handleSummary(data) {
  return {
    stdout: textSummary(data),
  };
}

function textSummary(data) {
  const httpReqs = data.metrics.http_reqs;
  const duration = data.metrics.http_req_duration;
  const failed = data.metrics.http_req_failed;
  return [
    "",
    "===== k6 summary (gateway) =====",
    `BASE_URL=${BASE_URL}${REQUEST_PATH}`,
    `http_reqs=${httpReqs ? httpReqs.values.count : "n/a"}`,
    `http_req_duration p95=${duration ? duration.values["p(95)"] : "n/a"} ms`,
    `http_req_failed rate=${failed ? failed.values.rate : "n/a"}`,
    "================================",
    "",
  ].join("\n");
}
