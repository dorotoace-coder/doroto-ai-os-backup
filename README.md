# doroto-ai-os-backup

Automated backup repository for **Doroto AI-OS** — the full stack powering Dee (OpenClaw), Claude Code Bridge, n8n workflows, launchd services, and all venture agents.

## What Gets Backed Up

| Source | Contents |
|--------|----------|
| `~/.openclaw/workspace/` | SOUL.md, ROUTING.md, AGENTS.md, HEARTBEAT.md, skills, memory |
| `~/.openclaw/agents/` | Max, Favour, Gabriel, Ace, Webb sub-agent workspaces |
| `~/.doroto/` | Scripts, bridge server, watchdog, webb prospects, bridge outputs |
| `~/Library/LaunchAgents/ai.doroto.*` | All Doroto launchd service plists |
| n8n workflows (API export) | All workflow JSON via n8n REST API |

## Backup Schedule

Managed by `~/.doroto/ai-os-backup-recovery/backup.sh`  
Triggered manually or via cron. Telegram notification on completion via n8n WF-Backup.

## Restore

See `restore.sh` in the source machine at `~/.doroto/ai-os-backup-recovery/`.

## Structure

```
doroto-ai-os-backup/
├── README.md
└── ai-os-backup-YYYYMMDDHHMMSS.zip   ← daily backup archives
```

---
*Maintained by Dee — Doroto's AI Chief of Staff*
