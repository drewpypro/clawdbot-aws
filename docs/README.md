# Documentation Index

This directory contains guides for setting up and securing the `clawdbot-aws` infrastructure.

## Reading Order

1. **[OpenClaw Setup & Operations](openclaw_setup.md)** — Install, configure, and manage OpenClaw on EC2
2. **[OpenClaw Security](openclaw_security.md)** — Threat model, credential management, execution controls, network security
3. **[Branch Protection & Rulesets](branch_protection.md)** — GitHub branch protection, CI/CD gates, bot account security

## About

These documents were collaboratively created by a human ([drewpypro](https://github.com/drewpypro)) and an AI bot ([drewpy-code-agent](https://github.com/drewpy-code-agent)) running [OpenClaw](https://github.com/openclaw/openclaw). They were reviewed by an AI security reviewer sub-agent (SecReview-9000).

Take everything with a grain of salt — further testing is needed. Always validate against official documentation before applying to production.

Security reviews were conducted by an AI sub-agent reviewer (SecReview-9000 / "Larry") and a separate Claude Opus 4.6 instance. Findings were independently verified before inclusion — unverified claims (including fabricated CVEs and vendor reports) were excluded.

> **⚠️ Caution:** This repo deploys infrastructure to AWS using Terraform. AI-managed infrastructure automation carries real financial risk and personal liability. See individual docs for details.
