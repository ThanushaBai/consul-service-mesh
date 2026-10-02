import http from 'k6/http';
import { check, sleep } from 'k6';
import { htmlReport } from "https://raw.githubusercontent.com/benc-uk/k6-reporter/main/dist/bundle.js";
import { textSummary } from "https://jslib.k6.io/k6-summary/0.0.1/index.js";

// Target URL is passed via env var: TARGET_URL
const TARGET_URL = __ENV.TARGET_URL || 'http://localhost:8081/';

export const options = {
  stages: [
    { duration: '30s', target: 10 },   // warm-up
    { duration: '30s', target: 50 },   // moderate load
    { duration: '30s', target: 100 },  // heavy load
    { duration: '10s', target: 0 },    // cool-down
  ],
  thresholds: {
    'http_req_duration': ['p(95)<1000'],  // 95% of requests under 1s
    'http_req_failed': ['rate<0.01'],      // <1% errors
  },
};

export default function () {
  const res = http.get(TARGET_URL);

  check(res, {
    'status is 200': (r) => r.status === 200,
    'response has backend data': (r) => r.body && r.body.includes('backend'),
  });

  sleep(0.1);  // tiny pause between requests per VU
}

export function handleSummary(data) {
  return {
    "stdout": textSummary(data, { indent: ' ', enableColors: true }),
    "/benchmarks/scripts/output/report.html": htmlReport(data),
  };
}