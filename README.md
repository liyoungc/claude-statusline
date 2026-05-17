# claude-statusline

Minimal Claude Code statusline with ccline-inspired color scheme.

```
Opus 4.7 (1M) [H] | 6% ░░░░░░░░░░ | myproject | main | ci:ok | 4'12" | 7d:8% | 5h:24%
```

## Segments

| Segment | Color | Description |
|---------|-------|-------------|
| Model | palette-M | Model name + context window size |
| Effort | red/yellow/dim | Reasoning effort: `[H]` / `[M]` / `[L]` / `[-]` (from `CLAUDE_EFFORT` env or `~/.claude/settings.json:effortLevel`) |
| Context | gradient | Usage % with block bar, color shifts violet → red as it fills |
| Directory | palette-DT | Current working directory |
| Git | palette-G | Branch + dirty indicator |
| CI Status | green/red/yellow | Latest GitHub Actions run |
| Cache | palette-C / yellow / red | 5 min prompt-cache idle timer |
| Rate Limits | palette-C / yellow / red | 5h and 7d usage % + elapsed-window % |

## Per-session color palettes

Eight coordinated palettes — `cyan`, `ocean`, `forest`, `sunset`, `lavender`, `rose`, `gold`, `mono`.

- **Auto** — each new session gets a palette deterministically from `cksum(session_id) mod 8`. Same session always renders the same colors (no flicker on refresh).
- **Manual override** — `/color` slash command re-rolls a random different palette for the current session. Arguments:
  - `/color` → random palette ≠ current
  - `/color ocean` (or any name) → switch to that palette
  - `/color next` → cycle to next palette in order
  - `/color clear` → drop the override, fall back to the deterministic hash

Override state lives in `~/.claude/statusline_palette/<session_id>` (one tiny file per session, just an integer 1-8).

Warning colors (CI fail / 80%+ rate limit / cache expired) stay fixed red/yellow across all palettes so semantics never break.

## Install

```sh
curl -sSfL https://raw.githubusercontent.com/liyoungc/claude-statusline/main/install.sh | sh
```

Or manually:

```sh
cp statusline.sh ~/.claude/hooks/statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "sh ~/.claude/hooks/statusline.sh"
  }
}
```

## Requirements

- `jq` (required)
- `git` (for branch/dirty status)
- `gh` (optional, for GitHub CI status)

## License

MIT
