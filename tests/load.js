import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 20 },
    { duration: '1m', target: 40 },
    { duration: '30s', target: 30 }
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<300','p(99)<500']
  }
};

export default function () {

  const res = http.get("http://docker-app-svc");

  check(res, {
    "status < 500": (r) => r.status < 500
  });

  sleep(1);
}
