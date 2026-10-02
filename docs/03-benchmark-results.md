# Consul Service Mesh — Benchmark Results

| Field | Value |
|---|---|
| **Department** | DevOps |
| **Prepared by** | Thanusha Bai V |
| **Date** | 02-Oct-2026 |
| **Subtask** | DEV-613/614 — Latency & Resource Benchmarks |
| **Parent Task** | DEV-610 — Consul Service Mesh |

---

## 1. Overview

This document presents the performance comparison between the **baseline** environment (direct HTTP, no proxy) and the **with-mesh** environment (Consul Connect + Envoy sidecars with mTLS), as deployed under DEV-612.

Two load-testing tools were used:

- **`hey`** — flat 50-user load for 60 seconds (constant pressure)
- **`k6`** — ramped load from 10 → 50 → 100 users over 100 seconds (realistic progression)

Resource usage (CPU / memory) was captured via `docker stats` during active load.

All raw outputs are stored under `benchmarks/results/` and HTML reports under `benchmarks/scripts/output/`.

---

## 2. Test Environment

| Component | Baseline | Mesh |
|-----------|----------|------|
| Application | Python 3.12 + Flask | Python 3.12 + Flask |
| Proxy | None | Envoy 1.28 (sidecar per service) |
| Encryption | None | mTLS (SPIFFE identities) |
| Control plane | None | Consul 1.18 |
| Intention enforcement | None | `frontend → backend: allow` |
| Host | Windows, Docker Desktop | Windows, Docker Desktop |
| Endpoint tested | `http://localhost:8081/` | `http://localhost:8081/` |

Both environments were tested with the **same endpoint** and **same load profiles** for an apples-to-apples comparison.

---

## 3. Latency & Throughput — `hey` Results

**Command:** `hey -z 60s -c 50 http://localhost:8081/`

| Metric | Baseline | Mesh | Delta | % Change |
|--------|----------|------|-------|----------|
| Total requests | ~10,845 | 10,177 | -668 | -6.2% |
| Throughput (req/sec) | 180.03 | 168.99 | -11.04 | **-6.1%** |
| Average latency | 277 ms | 295 ms | +18 ms | **+6.5%** |
| P50 latency | 267 ms | 288 ms | +21 ms | +7.9% |
| P90 latency | 331 ms | 335 ms | +4 ms | +1.2% |
| P95 latency | 348 ms | 360 ms | +12 ms | +3.4% |
| P99 latency | 386 ms | 461 ms | +75 ms | +19.4% |
| Max latency | 533 ms | 645 ms | +112 ms | +21.0% |
| Error rate | 0% | 0% | — | — |

**Interpretation:** Under flat high-concurrency load, the mesh adds ~18 ms average latency (+6.5%) and reduces throughput ~6%. Tail latency (P99) suffers more (+19%) due to mTLS handshake overhead and the additional proxy hop.

---

## 4. Latency & Throughput — `k6` Results

**Command:** `k6 run benchmark.js` (100s ramp: 10 → 50 → 100 → 0 users)

| Metric | Baseline | Mesh | Delta | % Change |
|--------|----------|------|-------|----------|
| Total requests | 14,404 | 13,309 | -1,095 | -7.6% |
| Throughput (req/sec) | 143.24 | 132.32 | -10.92 | **-7.6%** |
| Average latency | 162.19 ms | 184.02 ms | +21.83 ms | **+13.5%** |
| Median (P50) | 160.26 ms | 176.03 ms | +15.77 ms | +9.8% |
| P90 latency | 332.19 ms | 366.05 ms | +33.86 ms | +10.2% |
| P95 latency | 376.34 ms | 388.11 ms | +11.77 ms | +3.1% |
| Max latency | 517.33 ms | 494.02 ms | -23 ms | -4.4% |
| Error rate | 0% | 0% | — | — |
| Checks passed | 28,808 / 28,808 | 26,618 / 26,618 | — | 100% both |

**Interpretation:** Under ramped load, the mesh adds ~22 ms average latency (+13.5%). The relative throughput drop is similar to `hey` (~7–8%). All checks passed on both sides — zero failures.

---

## 5. Resource Usage — CPU & Memory

Captured during a 60-second `hey` load test.

### Baseline Environment

| Container | CPU % | Memory |
|-----------|-------|--------|
| `baseline-backend` | 14.85% | 55.92 MiB |
| `baseline-frontend` | 0.02% | 45.36 MiB |
| **Total** | **14.87%** | **~101 MiB** |

### Mesh Environment

| Container | CPU % | Memory |
|-----------|-------|--------|
| `mesh-backend` | 44.78–47.25% | ~28 MiB |
| `mesh-backend-agent` | 0.41–0.90% | ~35 MiB |
| `mesh-backend-sidecar` | 28.66–31.97% | ~34 MiB |
| `mesh-frontend` | 117–121% | ~35 MiB |
| `mesh-frontend-agent` | 0.41–1.78% | ~36 MiB |
| `mesh-frontend-sidecar` | 31.69–34.19% | ~45 MiB |
| `consul-server` | 1.18–1.22% | ~36 MiB |
| **Total** | **~225–240%** | **~250 MiB** |

### Resource Overhead Summary

| Metric | Baseline | Mesh | Overhead |
|--------|----------|------|----------|
| **Total CPU** | ~15% | ~230% | **+215%** |
| **Total Memory** | ~101 MiB | ~250 MiB | **+148%** |
| **Container count** | 2 | 7 | +5 containers |

**Note:** CPU% in Docker can exceed 100% for multi-threaded workloads across multiple cores. The frontend spike (~120%) is due to the Python process handling 50 concurrent inbound requests plus synchronous outbound calls through the sidecar.

---

## 6. Key Findings

### 6.1 Latency Overhead

- **`hey` (flat load):** +18 ms average (+6.5%)
- **`k6` (ramped load):** +22 ms average (+13.5%)
- **Tail latency (P99):** up to +75 ms under flat high-concurrency load

The mesh's overhead is dominated by:
1. **mTLS handshake** — certificate exchange and validation per new TCP connection
2. **Extra proxy hop** — every request passes through two Envoy sidecars
3. **L7 processing** — Envoy inspects and routes traffic at the application layer

### 6.2 Throughput Impact

- **~6–8% throughput drop** in both test runs
- Consistent across flat and ramped load profiles

### 6.3 CPU Overhead

- **~15× increase in aggregate CPU** (from ~15% to ~230%)
- The two Envoy sidecars alone consume **~60–65% CPU** under load
- The two Consul agents add ~1–2% (minimal)
- The Consul server adds ~1% (minimal)
- The application containers themselves consume more CPU under the mesh — likely due to context switching and additional HTTP round-trips within the shared namespace

### 6.4 Memory Overhead

- **~2.5× increase in aggregate memory** (from ~101 MiB to ~250 MiB)
- Each sidecar/agent/server averages ~35–45 MiB
- Memory usage is stable — no leaks observed over the 60-second test

### 6.5 Reliability

- **Zero errors on both environments** across ~45,000 total requests
- **100% check pass rate** in `k6`
- mTLS encryption and intention enforcement did not cause any dropped requests

---

## 7. Trade-Off Analysis

| Dimension | Cost of Mesh | Benefit of Mesh |
|-----------|--------------|-----------------|
| Latency | +6–13% | Automatic mTLS |
| Throughput | -6–8% | Identity-based auth |
| CPU | ~15× | Traffic observability |
| Memory | ~2.5× | Zero-trust networking |
| Ops complexity | +5 containers | Policy centralization |

**The overhead is real but bounded.** For workloads where security and observability outweigh raw throughput — multi-tenant, regulated, cross-team microservices — the mesh's cost is justified.

For internal, low-sensitivity, high-throughput services — or for systems already behind a network boundary — the mesh may be overkill.

---

## 8. Files & Artifacts

| File | Description |
|------|-------------|
| `benchmarks/scripts/benchmark.js` | k6 load test script |
| `benchmarks/results/baseline-hey.txt` | Baseline `hey` output |
| `benchmarks/results/baseline-k6.txt` | Baseline `k6` output |
| `benchmarks/results/baseline-stats.txt` | Baseline CPU/memory stats |
| `benchmarks/results/mesh-hey.txt` | Mesh `hey` output |
| `benchmarks/results/mesh-k6.txt` | Mesh `k6` output |
| `benchmarks/results/mesh-stats.txt` | Mesh CPU/memory stats |
| `benchmarks/scripts/output/baseline-report.html` | Baseline k6 HTML report |
| `benchmarks/scripts/output/mesh-report.html` | Mesh k6 HTML report |

---

## 9. Link to Subsequent Subtasks

This benchmark provides data for:

| Subtask | What it builds on from this doc |
|---------|--------------------------------|
| **DEV-615** | Understand failover cost in the context of mesh overhead |
| **DEV-616** | Quantify the security benefits that justify the overhead |
| **DEV-617** | Consolidate into the final comparison report |
| **DEV-618** | Recommend when to use a service mesh |

---

## 10. Conclusion

The Consul service mesh adds **measurable but bounded overhead** to service-to-service communication:

- **~20 ms average latency** added per request
- **~6–8% throughput** reduction
- **~2.5× memory** usage
- **~15× CPU** usage

These costs are the price of:
- Automatic mTLS encryption
- Identity-based authorization
- Zero-trust networking
- Traffic observability

The benchmark confirms the hypotheses outlined in DEV-611 and quantifies exactly what a team trades for these capabilities. Under real production workloads, the overhead depends on request patterns, service count, and network topology — but the order of magnitude measured here (~10% latency) is representative.

---

*End of Report*