# claude-statusline

Minimal Claude Code statusline with ccline-inspired color scheme.

```
Opus 4.6 (1M) | 6% ░░░░░░░░░░ | myproject | main | ci:ok | 5h 24% 2h0m 7d 8%
```

## Segments

| Segment | Color | Description |
|---------|-------|-------------|
| Model | cyan | Model name + context window size |
| Context | magenta | Usage % with block bar |
| Directory | green | Current working directory |
| Git | blue | Branch + dirty indicator |
| CI Status | green/red/yellow | Latest GitHub Actions run |
| Rate Limits | cyan/yellow/red | 5h and 7d usage, remaining time |

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
