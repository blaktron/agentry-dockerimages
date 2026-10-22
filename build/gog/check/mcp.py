"""Drive `gog mcp` over stdio, as an MCP client would, for scripts/check.sh.

    python3 -I mcp.py <argv that starts the server>...

Sends initialize, then tools/list, then calls the first tool (by name) that
takes no argument, with nobody signed in. Prints `protocol <version>`,
`capability <name>` per capability, `tool <name> read` or `tool <name>
change` per tool, and `call-error <text>` with the call's error text, or
`call-ok` when the call did not fail. A tool is `read` only when its MCP
annotations say readOnlyHint true; a tool with no annotation is `change`.
Exits 1 when the server does not answer, answers out of turn, or exits
early. It sets no timeout of its own on a read: the caller runs it under one.
"""

import json
import subprocess
import sys


def main() -> int:
    argv = sys.argv[1:]
    if not argv:
        print("usage: mcp.py <argv>...", file=sys.stderr)
        return 2
    p = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

    def send(msg):
        p.stdin.write(json.dumps(msg) + "\n")
        p.stdin.flush()

    def answer(want_id):
        while True:
            line = p.stdout.readline()
            if not line:
                raise RuntimeError(f"the server closed its output before answering {want_id}")
            msg = json.loads(line)
            if "id" not in msg:
                continue
            if msg["id"] != want_id:
                raise RuntimeError(f"an answer to {msg['id']} came before {want_id}")
            if "error" in msg:
                raise RuntimeError(f"request {want_id} failed: {msg['error']}")
            return msg["result"]

    try:
        send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-06-18", "capabilities": {},
            "clientInfo": {"name": "agentry-dockerimages-check", "version": "1"}}})
        init = answer(1)
        print("protocol", init["protocolVersion"])
        for cap in sorted(init.get("capabilities", {})):
            print("capability", cap)
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})
        tools = sorted(answer(2)["tools"], key=lambda t: t["name"])
        for t in tools:
            ro = (t.get("annotations") or {}).get("readOnlyHint") is True
            print("tool", t["name"], "read" if ro else "change")
        bare = [t["name"] for t in tools
                if not (t.get("inputSchema") or {}).get("required")]
        if bare:
            send({"jsonrpc": "2.0", "id": 3, "method": "tools/call",
                  "params": {"name": bare[0], "arguments": {}}})
            res = answer(3)
            if res.get("isError"):
                text = " ".join(c.get("text", "") for c in res.get("content", []))
                print("call-error", " ".join(text.split()))
            else:
                print("call-ok")
        p.stdin.close()
        p.wait()
    except (RuntimeError, ValueError, KeyError) as e:
        print(f"mcp.py: {e}", file=sys.stderr)
        p.kill()
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
