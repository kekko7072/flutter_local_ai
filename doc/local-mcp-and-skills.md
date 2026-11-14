# Attach flutter_local_ai docs locally with MCP

A local filesystem MCP server lets a coding assistant read the package API,
example, platform docs, and bundled skill while it works in your application.
It does not expose credentials or run inference. Replace `<PACKAGE_PATH>` with
this repository checkout or the package directory in your pub cache.

## Codex

Add this to `~/.codex/config.toml`:

```toml
[mcp_servers.flutter_local_ai]
command = "npx"
args = ["-y", "@modelcontextprotocol/server-filesystem", "<PACKAGE_PATH>"]
```

Copy the routed skill into the app or your user skill directory:

```bash
mkdir -p .codex/skills
cp -R <PACKAGE_PATH>/skills/flutter-local-ai .codex/skills/
```

Restart Codex, then invoke `$flutter-local-ai` or ask it to configure the
package. Keep the full folder: `SKILL.md` routes to platform-specific files in
`references/`.

## Claude Code

Add a project `.mcp.json`:

```json
{
  "mcpServers": {
    "flutter_local_ai": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "<PACKAGE_PATH>"]
    }
  }
}
```

Then copy the same folder to `.claude/skills/flutter-local-ai`.

## Recommended scope

Expose only the package directory, not a home directory. The useful resources
are `README.md`, `doc/`, `lib/`, `example/`, and `skills/flutter-local-ai/`.
The skill tells the assistant to keep on-device inference as the default,
distinguish Apple PCC from Android Firebase cloud, gate capabilities at
runtime, and test application logic with `FakeLocalAiHost`.
