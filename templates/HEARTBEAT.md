# HEARTBEAT — Memento Memory Maintenance

> OpenClaw reads this file every 30 minutes. Evaluate each condition below.
> Act only if the condition is true. Reply HEARTBEAT_OK if nothing needs doing.
> Do NOT tick off these items — they are standing instructions, not a to-do list.

---

- [ ] If `openclaw memory status` shows `Dirty: yes` → run `openclaw memory index`
- [ ] If meaningful conversation has happened since last capture → run memory capture, update `RECENT_CONTEXT.md` with highlights from recent turns
- [ ] If the current task or project context has shifted → update `SESSION-STATE.md` to reflect the new state
- [ ] If `memory/episodic/` contains more than 30 files → consider running consolidation to keep the store compact
- [ ] If `RECENT_CONTEXT.md` has not been updated in more than 24 hours and sessions have been active → refresh it with a summary of recent activity

<!-- END MEMENTO HEARTBEAT -->
