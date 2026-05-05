# Deployment Ledger

This directory is populated automatically by the deploy workflow. Each successful
deployment writes a JSON record here, then the workflow commits it to the
`deployments-ledger` branch (kept separate from `main` so the ledger has its own
history and can be audited without polluting the codebase).

A record looks like:

```json
{
  "environment": "sfprod",
  "timestamp": "2026-05-05T14:32:11Z",
  "actor": "harshil",
  "commit": "abc123...",
  "ref": "main",
  "run_id": "1234567890",
  "deploy_id": "0Af...",
  "validation_id": "0Af...",
  "quick_deploy": true,
  "test_level": "RunAllTestsInOrg",
  "outcome": "success"
}
```

To browse the ledger: `git checkout deployments-ledger && ls deployments/`.
