# MCP Tools Usage Guide

Quick reference for using the homelab MCP tools within Claude Code sessions.

## When to Use MCP Tools

Use MCP tools when you need repository metadata that would otherwise require file parsing:

- ✅ **Use MCP**: "What's the IP address of the VPS?" → `get_machine_ip`
- ❌ **Don't use MCP**: "What's in the pebble README?" → Use `Read` tool directly

- ✅ **Use MCP**: "List all homelab services" → `list_services`
- ❌ **Don't use MCP**: "Read the caddy module" → Use `Read` tool directly

- ✅ **Use MCP**: "Where is the kanidm service module?" → `get_service_path`
- ❌ **Don't use MCP**: "What port does kanidm use?" → Read the module directly

**Rule of thumb:** Use MCP for metadata queries. Use Read/Glob/Grep for file contents.

## Tool Reference

### `get_machine_ip`

Get IP address from `machines/nixos/vars.nix` without parsing the file.

**Example:**
```
User: "Deploy to the VPS"
Claude: [calls get_machine_ip with machine="vps"]
Tool returns: "204.168.181.110"
Claude: "Running deploy command to 204.168.181.110..."
```

**Valid machines:** `pebble`, `vps`

**Returns:** IP address as string (e.g., `192.168.10.50`)

---

### `list_services`

List all directories under `homelab/` that contain `default.nix`.

**Example:**
```
User: "How many services are deployed?"
Claude: [calls list_services]
Tool returns: ["backup", "caddy", "grafana", ...]
Claude: "There are 15 services deployed: backup, caddy, grafana..."
```

**Returns:** JSON array of service names (sorted alphabetically)

---

### `get_service_path`

Get absolute path to a service module directory.

**Example:**
```
User: "Add a new config to kanidm"
Claude: [calls get_service_path with service="kanidm"]
Tool returns: "/Users/.../lab/homelab/kanidm"
Claude: [uses Read tool on /Users/.../lab/homelab/kanidm/default.nix]
```

**Returns:** Absolute path as string

**Error handling:** Returns error message if service doesn't exist

## Performance Characteristics

### MCP tools are FAST ⚡

- Cached by Claude Code for the session
- No file I/O overhead (runs once, result reused)
- No LLM token overhead for parsing

### Example: Getting all service paths

**Without MCP** (slow):
1. Glob `homelab/*/default.nix` → file list
2. For each file, construct path manually
3. Verify each path exists
4. Total: 3 tool calls + token overhead

**With MCP** (fast):
1. Call `list_services` → service list (cached)
2. For each service, call `get_service_path` → path (cached)
3. Total: 1 + N tool calls, all cached, minimal tokens

## Best Practices

### ✅ DO:
- Use `get_machine_ip` when constructing deploy/SSH commands
- Use `list_services` to enumerate services for batch operations
- Use `get_service_path` to resolve paths before reading files
- Cache results mentally in your context (MCP tools return the same data within a session)

### ❌ DON'T:
- Use MCP tools for file contents (use Read instead)
- Call MCP tools redundantly (results are cached, but still costs a tool call)
- Assume service names (use `list_services` to get the canonical list)
- Hard-code IPs (use `get_machine_ip` so they stay in sync with vars.nix)

## Troubleshooting

### "MCP server not connected"

Check server status:
```bash
claude mcp list
```

If server shows `✗ Failed to connect`:
```bash
cd .agent/mcp
./setup-venv.sh
```

### "Service 'foo' not found"

The service doesn't exist under `homelab/foo/`. List available services:
```
Claude: [calls list_services]
```

### "No module named 'homelab_mcp'"

The venv is missing dependencies. Reinstall:
```bash
cd .agent/mcp
rm -rf venv
./setup-venv.sh
```

## Future Tools (Planned)

Ideas for additional MCP tools:

- `get_service_ports` — extract port assignments from a service module
- `get_secret_keys` — list sops-nix secrets declared for a service
- `validate_nix_option` — check if a NixOS option exists (avoid inventing options)
- `get_service_readme` — read and parse service README.md metadata
- `list_stages` — enumerate roadmap stages and their completion status

See `PLAN.md` for prioritization.
