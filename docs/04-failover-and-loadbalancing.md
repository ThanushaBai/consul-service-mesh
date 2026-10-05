# Consul Service Mesh — Failover & Load Balancing

| Field | Value |
|---|---|
| **Department** | DevOps |
| **Prepared by** | Thanusha Bai V |
| **Date** | 05-Oct-2026 |
| **Subtask** | DEV-615 — Test Failover and Load Balancing |
| **Parent Task** | DEV-610 — Consul Service Mesh |

---

## 1. Overview

This document captures the failover, load-balancing, and authorization behavior of the Consul service mesh deployed under DEV-612. Four distinct scenarios were tested:

1. **Load balancing** — 3 backend replicas behind one frontend
2. **Pod-level failover** — killing an entire replica (agent + app + sidecar)
3. **Intention denial** — flipping authorization from allow to deny
4. **Health-check failover** — killing only the app while the pod stays alive

Each test used `hey` for continuous load and Consul's HTTP API / Envoy's admin API for observability.

---

## 2. Test Environment

| Component | Setup |
|-----------|-------|
| Backend replicas | 3 (`backend-1`, `backend-2`, `backend-3`) |
| Frontend | 1 |
| Consul server | 1 (dev mode, in-memory state) |
| Sidecar proxy | Envoy 1.28 per service |
| Load driver | `hey` (Docker image `williamyeh/hey`) |
| Endpoint tested | `http://localhost:8081/` |

Each backend replica runs as a group of three containers sharing a namespace (agent + app + sidecar).

---

## 3. Phase 1 — Load Balancing Across 3 Replicas

### 3.1 Test Setup

Fired 100 requests through the mesh with 5 concurrent workers.

```bash
docker run --rm --network host williamyeh/hey -n 100 -c 5 http://localhost:8081/
```

### 3.2 Evidence

Envoy's endpoint view before the test — all 3 healthy:

```
backend.default.dc1...::172.18.0.3:21000::healthy   (backend-1)
backend.default.dc1...::172.18.0.5:21000::healthy   (backend-2)
backend.default.dc1...::172.18.0.4:21000::healthy   (backend-3)
```

Request distribution after 100 requests:

```
172.18.0.3:21000::rq_total::33
172.18.0.5:21000::rq_total::34
172.18.0.4:21000::rq_total::34
```

### 3.3 Conclusion

Requests are distributed **evenly** across all 3 replicas (33 / 34 / 34), confirming round-robin load balancing. No replica was preferred; no replica was starved.

---

## 4. Phase 2 — Pod-Level Failover

### 4.1 Test Setup

- 120-second load test with `hey -z 120s -c 10`
- Mid-test, killed the entire replica-2 pod:

```bash
docker stop mesh-backend-agent-2
```

Stopping the agent tears down its shared network namespace, taking the app and sidecar with it.

### 4.2 Evidence — Before Kill

```
172.18.0.3:21000::healthy   (backend-1)
172.18.0.5:21000::healthy   (backend-2)
172.18.0.4:21000::healthy   (backend-3)
```

### 4.3 Evidence — After Kill (~15 seconds later)

```
172.18.0.3:21000::healthy   (backend-1)
172.18.0.4:21000::healthy   (backend-3)
(172.18.0.5 disappeared from Envoy's load balancer)
```

### 4.4 Load Test Result

| Metric | Value |
|--------|-------|
| Total duration | 120.03 s |
| Total requests | 19,144 |
| Throughput | 159.50 req/s |
| Average latency | 62.7 ms |
| P95 latency | 89.0 ms |
| P99 latency | 113.1 ms |
| **Errors** | **0** |
| Status codes | 100% `[200]` |

### 4.5 Conclusion

**Zero errors over the entire 120-second test, despite a mid-test pod failure.** Envoy detected the dead endpoint via Consul's service catalog and immediately rerouted 100% of traffic to the surviving replicas. The frontend application was unaware of the failure.

---

## 5. Phase 2b — Recovery

### 5.1 Test Setup

Restarted replica 2's containers in order (agent → app → sidecar):

```bash
docker start mesh-backend-agent-2
Start-Sleep -Seconds 10
docker start mesh-backend-2
Start-Sleep -Seconds 3
docker start mesh-backend-sidecar-2
```

### 5.2 Evidence — After Recovery

Cluster membership:

```
backend-node-2  172.18.0.5:8301  alive   client  1.18.2  dc1
```

Envoy endpoint view — all 3 healthy again:

```
172.18.0.3:21000::healthy   (backend-1)
172.18.0.4:21000::healthy   (backend-3)
172.18.0.5:21000::healthy   (backend-2 — rejoined)
```

Request distribution after 90 new requests:

```
172.18.0.3:21000::rq_total::9230   (+30)   backend-1
172.18.0.4:21000::rq_total::9228   (+31)   backend-3
172.18.0.5:21000::rq_total::29     (+29)   backend-2
```

### 5.3 Conclusion

The recovered replica automatically rejoined the mesh **without any client-side configuration**. Load balancing returned to 3-way distribution immediately after Envoy marked the endpoint healthy.

---

## 6. Phase 3 — Intention Denial

### 6.1 Test Setup

Flipped the intention from allow to deny:

```bash
docker exec consul-server consul intention delete frontend backend
docker exec consul-server consul intention create -deny frontend backend
```

### 6.2 Evidence

Intention check:

```
$ docker exec consul-server consul intention check frontend backend
Denied
```

Request to the frontend:

```
$ curl.exe http://localhost:8081/
{"backend_url_used":"http://localhost:9191","error":"('Connection aborted.',
RemoteDisconnected('Remote end closed connection without response'))",
"service":"frontend"}
```

### 6.3 Conclusion

When the intention was flipped to deny, the frontend's **Envoy sidecar refused to open the mTLS connection** to the backend sidecar. The connection was reset cleanly (no partial data leaked). The frontend application received a network error — its own sidecar blocked the request before it left the pod. **Zero-trust enforcement at the data plane, transparent to the application.**

---

## 7. Phase 4 — Health-Check Failover (App-Only Failure)

### 7.1 Test Setup

- 120-second load test with `hey -z 120s -c 10`
- Mid-test, killed **only the app container**:

```bash
docker stop mesh-backend-2
```

The agent and sidecar remained running. Only the app process died.

### 7.2 Evidence — Consul Detected the Failure

```
backend-2 check: Status = critical
Output: Get "http://localhost:8080/health": dial tcp [::1]:8080: connection refused
```

Consul's HTTP health check failed (5s interval, 2 failures required to mark critical).

### 7.3 Evidence — Envoy Removed the Endpoint

```
172.18.0.3:21000::healthy              (backend-1)
172.18.0.5:21000::/failed_eds_health   (backend-2)
172.18.0.4:21000::healthy              (backend-3)
```

### 7.4 Request Distribution

```
172.18.0.3:21000::rq_total::17863   backend-1
172.18.0.4:21000::rq_total::17859   backend-3
172.18.0.5:21000::rq_total::922     backend-2 (frozen — no new requests)
```

### 7.5 Load Test Result

| Metric | Value |
|--------|-------|
| Total duration | 120.07 s |
| Total requests | 18,417 |
| Throughput | 153.38 req/s |
| Average latency | 65.2 ms |
| P95 latency | 105.1 ms |
| P99 latency | 144.0 ms |
| Status codes | 18,150 × `[200]`, **267 × `[502]`** |
| **Error rate** | **1.45%** |

### 7.6 Conclusion

Health-check-based failover works but introduces a **~10–15 second detection window** during which a small percentage of requests fail (1.45% in this test). All 502 errors occurred during that window. Once Consul marked the service critical, Envoy rerouted 100% of traffic to the surviving replicas.

**Trade-off:** Health checks catch things TCP errors cannot (e.g., a hung app that still accepts connections), but they add detection latency.

### 7.7 Recovery

Restarted the app container:

```bash
docker start mesh-backend-2
```

Within ~20 seconds, Envoy marked the endpoint healthy again and traffic resumed 3-way distribution.

---

## 8. Comparison of Failover Mechanisms

| Mechanism | Detection Trigger | Detection Time | Errors During Failover |
|-----------|-------------------|----------------|------------------------|
| **Pod kill (Phase 2)** | TCP-level connection refused | Instant (<1s) | 0 |
| **App kill (Phase 4)** | Health check failure | 10–15s | 267 (1.45%) |
| **Intention deny (Phase 3)** | Policy change | Immediate | N/A (intentional block) |

---

## 9. Key Findings

1. **Load balancing is automatic and even** — Envoy distributes requests uniformly across all healthy replicas without any client-side config.
2. **Pod-level failure triggers instant failover** — Zero errors when a container disappears; Envoy reacts to the TCP failure.
3. **Health-check-based failover has a detection window** — ~1.5% of requests fail during the ~10–15s window between app death and Envoy rerouting.
4. **Intentions enforce authorization strictly** — Flipping to deny instantly blocks traffic at the data plane.
5. **Recovery is fully automatic** — Restarted replicas rejoin the mesh and receive traffic without intervention.
6. **Zero-trust networking works transparently** — Applications never knew their traffic was being rerouted, blocked, or encrypted.

---

## 10. Files & Artifacts

| File | Description |
|------|-------------|
| `benchmarks/results/dev615-phase2-failover.txt` | Phase 2 evidence (pod kill + recovery) |
| `benchmarks/results/dev615-phase3-intention-denial.txt` | Phase 3 evidence (deny intention) |
| `benchmarks/results/dev615-phase4-health-failover.txt` | Phase 4 evidence (app kill + recovery) |
| `deployment/with-mesh/docker-compose.yml` | 13-container mesh deployment |
| `deployment/with-mesh/consul-config/*.hcl` | Service registrations for all replicas |

---

## 11. Link to Subsequent Subtasks

This document provides data for:

| Subtask | What it builds on from this doc |
|---------|--------------------------------|
| **DEV-616** | Security benefits — intentions and mTLS enforcement proven here |
| **DEV-617** | Performance comparison report — failover trade-offs documented |
| **DEV-618** | Recommendation — when a mesh's failover is worth the overhead |

---

## 12. Conclusion

The Consul service mesh delivers **production-grade failover, load balancing, and authorization** with zero application changes:

- **Even 3-way load distribution** confirmed across all backends
- **Zero errors** during pod-level failure (instant TCP detection)
- **1.5% errors** during app-level failure (health-check detection window)
- **Instant blocking** when intentions are set to deny
- **Automatic recovery** when failed replicas come back online

The small error rate during app-level failure (Phase 4) is the cost of relying on HTTP health checks instead of immediate TCP failure signals. In practice, this is acceptable for most workloads — the mesh is not a replacement for app-level resilience, but it dramatically simplifies service-to-service reliability.

---

*End of Report*