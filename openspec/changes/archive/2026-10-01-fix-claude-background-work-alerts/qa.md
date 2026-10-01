# QA: fix-claude-background-work-alerts

## Real Claude Code payload through the app's hook script

The hook script body was extracted verbatim from `writeHookLogScript()` on the implementation branch, with only the log path pointed at `/tmp/asm-prove/hooklog.jsonl`. It was registered as the `UserPromptSubmit` and `Stop` hook for a real `claude -p` run on Claude Code 2.1.286.

The logged lines, with `session_id` and `transcript_path` removed:

```json
{"hook_event_name": "UserPromptSubmit", "notification_type": null, "message": null, "agent_id": null, "agent_type": "coordinator", "timestamp": 1790860425.749839}
{"hook_event_name": "Stop", "notification_type": null, "message": null, "agent_id": null, "agent_type": "coordinator", "timestamp": 1790860436.192406, "background_tasks": [], "session_crons": []}
```

This shows that a real Claude Code `Stop` carries both lists, that the script records them under the keys the app decodes, and that events without the lists (`UserPromptSubmit`) record no list keys. A `Stop` with both lists empty is the "finished" golden path.

## Not yet demonstrated live

A live run with a background task still running at `Stop` was not captured. The attempt to launch a nested Claude Code run that starts a background shell command was blocked by the session's permission check. The non-empty-list behavior is covered by unit tests that use the documented payload shape from the Claude Code hooks reference.
