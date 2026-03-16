import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 3,
  duration: '30s',
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<300']
  }
};

export default function () {

  const res = http.get("http://docker-app-svc");

  check(res, {
    "status < 500": (r) => r.status < 500
  });

  sleep(1);
}
