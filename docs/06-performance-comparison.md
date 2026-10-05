# Consul Service Mesh — Performance Comparison

| Field | Value |
|---|---|
| **Department** | DevOps |
| **Prepared by** | Thanusha Bai V |
| **Date** | 05-Oct-2026 |
| **Subtask** | DEV-617 — Create Performance Comparison Report |
| **Parent Task** | DEV-610 — Consul Service Mesh |

---

## 1. Overview

This document consolidates all performance data collected during DEV-613/614 (latency, CPU, memory) and DEV-615 (failover behavior). It presents a side-by-side comparison of the baseline environment (direct HTTP) and the mesh environment (Consul Connect + Envoy sidecars with mTLS), and analyzes the trade-offs.

---

## 2. Test Environment

| Component | Baseline | Mesh |
|-----------|----------|------|
| Application | Python 3.12 + Flask | Python 3.12 + Flask |
| Proxy | None | Envoy 1.28 |
| Encryption | None | mTLS |
| Backend replicas | 1 | 3 |
| Service discovery | Docker DNS | Consul catalog |
| Authorization | None | Intentions |
| Host | Windows, Docker Desktop | Windows, Docker Desktop |

For apples-to-apples comparison, both environments were tested against the **same endpoint**: `http://localhost:8081/`.

---

## 3. Latency Comparison

### 3.1 `hey` Flat-Load Test (60s, 50 concurrent users)

| Metric | Baseline | Mesh | Delta |
|--------|----------|------|-------|
| Throughput (req/s) | 180.03 | 168.99 | -6.1% |
| Average latency | 277 ms | 295 ms | +18 ms (+6.5%) |
| P50 | 267 ms | 288 ms | +21 ms |
| P95 | 348 ms | 360 ms | +12 ms |
| P99 | 386 ms | 461 ms | +75 ms (+19%) |
| Errors | 0% | 0% | — |

### 3.2 `k6` Ramped-Load Test (100s, 10 → 100 users)

| Metric | Baseline | Mesh | Delta |
|--------|----------|------|-------|
| Throughput (req/s) | 143.24 | 132.32 | -7.6% |
| Average latency | 162.19 ms | 184.02 ms | +21.83 ms (+13.5%) |
| P50 | 160.26 ms | 176.03 ms | +15.77 ms |
| P90 | 332.19 ms | 366.05 ms | +33.86 ms |
| P95 | 376.34 ms | 388.11 ms | +11.77 ms |
| Errors | 0% | 0% | — |

**Conclusion:** The mesh adds **~18–22 ms average latency** (~6–13%) per request. Tail latency is affected more strongly under flat high-concurrency load.

---

## 4. Resource Usage Comparison

Measured via `docker stats` during a 60-second `hey` load test.

### 4.1 CPU

| Container | Baseline | Mesh | Notes |
|-----------|----------|------|-------|
| Backend app | 14.85% | 44–47% | Per replica, includes sidecar namespace |
| Frontend app | 0.02% | 117–121% | Multi-threaded under mesh |
| Backend sidecar | — | 28–32% | Envoy per replica |
| Frontend sidecar | — | 31–34% | Envoy |
| Backend agents | — | ~1% each | Consul client |
| Frontend agent | — | ~1% | Consul client |
| Consul server | — | ~1% | Control plane |
| **Aggregate** | **~15%** | **~230%** | **~15× increase** |

### 4.2 Memory

| Environment | Total Memory |
|-------------|--------------|
| Baseline | ~101 MiB |
| Mesh | ~250 MiB |
| **Overhead** | **~2.5×** |

Each mesh-related container (sidecar, agent, server) averages ~35–45 MiB.

---

## 5. Failover Behavior Comparison

Data from DEV-615.

| Scenario | Baseline Behavior | Mesh Behavior |
|----------|-------------------|---------------|
| Kill one backend replica | Frontend errors — no failover | Zero errors, traffic rerouted instantly |
| Kill app only (health check) | N/A | ~10–15s detection, 1.45% errors during window |
| Recover replica | Manual restart + config | Automatic rejoin, resume traffic |
| Block service (auth) | Not possible | Instant deny via intention |

### 5.1 Failover Latency

| Mechanism | Detection | Errors |
|-----------|-----------|--------|
| Pod kill (TCP refused) | Instant | 0 |
| App kill (health check) | 10–15s | ~1.5% |

---

## 6. Cost-Benefit Summary

| Dimension | Cost | Benefit |
|-----------|------|---------|
| Latency | +18–22 ms (6–13%) | mTLS encryption, identity auth |
| Throughput | -6–8% | Reliable failover, load balancing |
| CPU | ~15× | Sidecars handle all mesh duties |
| Memory | ~2.5× | Per-container overhead |
| Container count | +5 per replica | Granular isolation |
| Ops complexity | Higher | Centralized policy |

---

## 7. Reliability Comparison

| Metric | Baseline | Mesh |
|--------|----------|------|
| Errors under normal load | 0% | 0% |
| Errors during pod failover | N/A (no failover) | 0% |
| Errors during app failover | N/A | 1.45% |
| Encryption failures | N/A | 0% |
| Authz bypass events | N/A | 0% |

---

## 8. Interpretation

### 8.1 The Mesh Is Not "Free"

Every request now traverses:
1. Frontend app → frontend sidecar (loopback)
2. Frontend sidecar → backend sidecar (mTLS over network)
3. Backend sidecar → backend app (loopback)

That's **2 extra hops** plus TLS handshake overhead. The cost is real.

### 8.2 The Cost Is Bounded

- Latency overhead is **~20 ms** — a consistent, predictable cost
- Throughput impact is **single-digit percentage**
- CPU/memory scale linearly with replica count

### 8.3 The Benefits Are Material

- **Zero-effort mTLS** — no per-service TLS libraries
- **Instant policy changes** — flip intentions without redeploying
- **Automatic failover** — no client-side changes needed
- **Centralized observability** — one place to see all traffic

---

## 9. Conclusion

The Consul service mesh introduces a **measurable but bounded performance overhead**: ~6–13% latency increase, ~6–8% throughput drop, ~15× CPU, ~2.5× memory. In exchange, it delivers automatic mTLS, identity-based authorization, transparent failover, and centralized observability — all without application changes.

Whether this trade-off is worth it depends on the workload, compliance requirements, and team maturity — analyzed in detail in `07-recommendation.md`.

---

*End of Report*