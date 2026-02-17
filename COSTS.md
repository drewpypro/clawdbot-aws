# Clawdbot AWS Cost Breakdown — 7-Day Test

Estimated costs for running Clawdbot (OpenClaw) on a `t3.medium` EC2 instance in `us-west-2` for a 7-day evaluation period.

## Observed Resource Usage (clawd01 — Day 1)

| Resource | Observed | Notes |
|----------|----------|-------|
| **RAM Usage** | ~785 MB | Gateway (~434 MB) + CLI (~55 MB) + TUI (~284 MB) |
| **CPU Load** | 0.03 - 0.07 | Very light — mostly idle between API calls |
| **Disk Usage** | ~1.5 GB | OpenClaw (~13 MB) + Node.js/nvm (~1.4 GB) + OS |
| **Network TX** | ~0.64 GB/day | Outbound API calls (Anthropic, Discord, Signal) |
| **Network RX** | ~0.05 GB/day | Inbound API responses |
| **Total Network** | ~4.9 GB/week | Mostly outbound (API request/response payloads) |

> **Note:** Usage was measured during active development/testing with frequent API calls, Discord polling (5-min cron), Signal polling (5-min cron), and multiple GitHub API operations. Normal steady-state usage may be lower.

## Instance Sizing: t3.medium

| Spec | Value |
|------|-------|
| vCPUs | 2 |
| Memory | 4 GB |
| Network | Up to 5 Gbps |
| EBS Bandwidth | Up to 2,085 Mbps |

**Why t3.medium?**
- OpenClaw uses ~785 MB RAM under active load — 4 GB gives comfortable headroom for OS + Node.js garbage collection spikes
- CPU usage is minimal (bursty on API calls, idle otherwise) — t3 burstable is ideal
- 2 vCPUs handles concurrent cron jobs and sub-agent spawning without issues

## 7-Day Cost Estimate

### Fixed Costs (Running 24/7)

| Resource | Pricing | 7-Day Cost |
|----------|---------|------------|
| **t3.medium On-Demand** | $0.0416/hr | **$6.99** |
| **EBS gp3 (30 GB)** | $0.08/GB-month | **$0.55** |
| **EBS gp3 IOPS** (3,000 baseline) | Free (included) | $0.00 |
| **EBS gp3 Throughput** (125 MB/s baseline) | Free (included) | $0.00 |
| **Elastic IP** (attached to running instance) | Free¹ | $0.00 |
| | **Subtotal (Fixed):** | **$7.54** |

> ¹ As of Feb 2024, AWS charges $0.005/hr ($0.84/week) for *all* public IPv4 addresses including those attached to running instances. See note below.

### Variable Costs (Usage-Based)

| Resource | Estimated Usage | Rate | 7-Day Cost |
|----------|----------------|------|------------|
| **Data Transfer Out** | ~4.5 GB/week | First 100 GB free² | **$0.00** |
| **Data Transfer In** | ~0.4 GB/week | Always free | **$0.00** |
| **Public IPv4 Address** | 168 hrs | $0.005/hr | **$0.84** |
| **EBS Snapshots** (optional) | ~2 GB (if enabled) | $0.05/GB-month | **$0.02** |
| | **Subtotal (Variable):** | **$0.86** |

> ² AWS Free Tier includes 100 GB/month of data transfer out. Clawdbot uses ~5 GB/week — well within limits.

### Total 7-Day Estimate

| Category | Cost |
|----------|------|
| Compute (t3.medium) | $6.99 |
| Storage (EBS gp3 30GB) | $0.55 |
| Public IPv4 | $0.84 |
| Data Transfer | $0.00 |
| Snapshots (optional) | $0.02 |
| **Total** | **$8.40** |

## Monthly Projection (if kept running)

| Resource | Monthly Cost |
|----------|-------------|
| t3.medium On-Demand | $30.37 |
| EBS gp3 (30 GB) | $2.40 |
| Public IPv4 | $3.60 |
| Data Transfer Out (~20 GB) | $0.00³ |
| **Total Monthly** | **~$36.37** |

> ³ Still within 100 GB free tier for data transfer.

## Cost Optimization Options

| Strategy | Savings | Monthly Cost |
|----------|---------|-------------|
| **On-Demand (baseline)** | — | $36.37 |
| **1-Year Reserved (No Upfront)** | ~27% | ~$26.55 |
| **1-Year Reserved (All Upfront)** | ~38% | ~$22.55 |
| **Spot Instance**⁴ | ~60-70% | ~$11-15 |
| **Run only during business hours** (12h/day) | ~50% compute | ~$20 |
| **t3.small** (2 vCPU, 2 GB RAM)⁵ | ~50% compute | ~$20 |

> ⁴ Spot instances can be interrupted — not ideal for a persistent assistant but works for testing.
> ⁵ Tight on RAM (2 GB vs ~785 MB used) — workable but less headroom. Monitor for OOM.

## What's NOT Included

These costs are **AWS infrastructure only**. Additional costs:

| Item | Cost | Notes |
|------|------|-------|
| **Anthropic API** (Claude) | $20-200/mo | Depends on plan (Max $200/mo for Opus) |
| **Domain/DNS** (optional) | $0-12/yr | If using a custom domain |
| **Cloudflare** (optional) | Free tier | Proxy/WAF if desired |

## Architecture Note

```
┌─────────────────────────────────────────┐
│  AWS EC2 (t3.medium)                    │
│  ┌───────────────────────────────────┐  │
│  │  Debian 12                        │  │
│  │  ├── Node.js 22 (via nvm)        │  │
│  │  ├── OpenClaw Gateway (~434 MB)   │  │
│  │  ├── OpenClaw CLI (~55 MB)        │  │
│  │  └── Integrations                 │  │
│  │      ├── Discord Bot              │  │
│  │      ├── Signal (signal-cli)      │  │
│  │      └── GitHub/Gitea API         │  │
│  └───────────────────────────────────┘  │
│  EBS gp3: 30 GB (encrypted)            │
│  SG: SSH (restricted) + HTTPS/DNS out  │
└─────────────────────────────────────────┘
         │
         ▼ API calls (HTTPS outbound)
   Anthropic / Discord / Signal / GitHub
```

## TL;DR

**7-day test: ~$8.40** — Less than two coffees. ☕☕

**Monthly if kept running: ~$36/mo** — Plus your Anthropic API plan.

---
*Generated by clawdbot based on observed usage data from clawd01 (Minisforum X1, Day 1) and AWS us-west-2 pricing as of February 2026.*
