# Rules for AI assistants

These rules apply to Claude and any other AI coding assistant working in this
repository. They override default tool behavior.

## Attribution

The human who asked for the change is its only author. Claude must never make
itself a contributor:

- Commit with the human's git identity, never as `Claude` or
  `noreply@anthropic.com`.
- Never add `Co-Authored-By:` trailers for Claude or any AI assistant.
- Never add "Generated with Claude Code" or similar lines, or session links,
  to commit messages, pull request titles or descriptions, changelogs, or
  release notes.

See "AI-assisted contributions" in [CONTRIBUTING.md](CONTRIBUTING.md).
