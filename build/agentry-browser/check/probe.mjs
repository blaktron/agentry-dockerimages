// The image check's probe (scripts/check.sh --browser-image), run inside a
// built agentry-browser with no network, by the image's own node, as its own
// user. It drives the image's @playwright/mcp over stdio, as the gateway
// does, against two servers of its own on loopback:
//
//   127.0.0.1:8080  the fixture page (fixture.html), over plain http at
//                   localhost, a secure context, so the client hints answer
//   127.0.0.1:8443  a listener that reads the TLS ClientHello Chromium sends
//                   and closes: the server name and whether it offers ECH
//
// Chromium reaches the listener as probe.test through --host-resolver-rules.
// Each step prints "ok   …" or "FAIL …"; the exit status is 1 on any FAIL.
//
//   node probe.mjs          the image as built: ECH must be off (its policy)
//   node probe.mjs control  the negative control, run with the policy folder
//                           hidden: ECH must be offered, which proves this
//                           listener sees it and the policy is what stops it
import { spawn } from "node:child_process";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import http from "node:http";
import net from "node:net";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const control = process.argv[2] === "control";
const out = "/out-browser";
let failed = false;
const ok = (m) => console.log(`ok   ${m}`);
const fail = (m) => {
	console.log(`FAIL ${m}`);
	failed = true;
};

// The secret the server types by name: a made-up value, which
// must never come back in a result.
const secretName = "CHECK_SECRET";
const secretValue = "probe-value-7f3a9c";

const fixture = readFileSync(join(here, "fixture.html"));
const web = http.createServer((req, res) => {
	res.writeHead(200, { "content-type": "text/html; charset=utf-8" });
	res.end(fixture);
});
await new Promise((r) => web.listen(8080, "127.0.0.1", r));

// hello records each ClientHello the TLS listener reads.
const hellos = [];
const tls = net.createServer((sock) => {
	let buf = Buffer.alloc(0);
	sock.on("data", (d) => {
		buf = Buffer.concat([buf, d]);
		if (buf.length < 5) return;
		const len = buf.readUInt16BE(3);
		if (buf.length < 5 + len) return;
		hellos.push(parseHello(buf.subarray(5, 5 + len)));
		sock.destroy();
	});
	sock.on("error", () => {});
});
await new Promise((r) => tls.listen(8443, "127.0.0.1", r));

// parseHello reads a ClientHello handshake message (RFC 8446 §4.1.2): its
// server_name and whether it carries encrypted_client_hello (0xfe0d).
function parseHello(b) {
	const h = { sni: "", ech: false };
	if (b[0] !== 1) return h;
	let i = 4 + 2 + 32;
	i += 1 + b[i];
	i += 2 + b.readUInt16BE(i);
	i += 1 + b[i];
	const end = i + 2 + b.readUInt16BE(i);
	i += 2;
	while (i + 4 <= end) {
		const type = b.readUInt16BE(i);
		const len = b.readUInt16BE(i + 2);
		const data = b.subarray(i + 4, i + 4 + len);
		if (type === 0xfe0d) h.ech = true;
		if (type === 0 && data.length > 5) h.sni = data.subarray(5, 5 + data.readUInt16BE(3)).toString();
		i += 4 + len;
	}
	return h;
}

writeFileSync("/tmp/browser-check.json", JSON.stringify({
	browser: {
		launchOptions: {
			// The runner decides the sandbox; a check container keeps
			// Docker's default seccomp profile, where Chromium's cannot start.
			chromiumSandbox: false,
			args: ["--host-resolver-rules=MAP *.test 127.0.0.1"],
		},
	},
}));
writeFileSync("/tmp/browser-check.env", `${secretName}=${secretValue}\n`);

const record = Object.fromEntries(readFileSync("/etc/agentry/browser/record", "utf8")
	.trim().split("\n").map((l) => [l.split(" ")[0], l.split(" ").slice(1)]));

const server = spawn("/usr/local/bin/node", [
	"/app/node_modules/@playwright/mcp/cli.js",
	"--headless", "--isolated", "--browser", "chromium", "--caps", "testing,pdf",
	"--output-dir", out, "--viewport-size", "1280x800",
	"--config", "/tmp/browser-check.json", "--secrets", "/tmp/browser-check.env",
], { stdio: ["pipe", "pipe", "pipe"] });
let stderr = "";
server.stderr.on("data", (d) => (stderr += d));
let pending = "";
const waiting = new Map();
server.stdout.on("data", (d) => {
	pending += d;
	let n;
	while ((n = pending.indexOf("\n")) >= 0) {
		const line = pending.slice(0, n);
		pending = pending.slice(n + 1);
		if (!line.trim()) continue;
		const msg = JSON.parse(line);
		if (msg.id !== undefined && waiting.has(msg.id)) {
			waiting.get(msg.id)(msg);
			waiting.delete(msg.id);
		}
	}
});
let nextID = 0;
function rpc(method, params) {
	const id = ++nextID;
	server.stdin.write(JSON.stringify({ jsonrpc: "2.0", id, method, params }) + "\n");
	return new Promise((resolve, reject) => {
		const t = setTimeout(() => reject(new Error(`${method}: no answer in 90 s; server stderr:\n${stderr}`)), 90000);
		waiting.set(id, (m) => {
			clearTimeout(t);
			resolve(m);
		});
	});
}
async function call(name, args) {
	const m = await rpc("tools/call", { name, arguments: args });
	const res = m.result || {};
	const text = (res.content || []).map((c) => c.text || "").join("\n");
	return { isError: !!res.isError || !!m.error, text: text || JSON.stringify(m.error || "") };
}

try {
	const init = await rpc("initialize", {
		protocolVersion: "2025-06-18", capabilities: {}, clientInfo: { name: "agentry-browser-check", version: "1" },
	});
	const version = init.result?.serverInfo?.version;
	version === record.playwright[0]
		? ok(`the server answers initialize as Playwright ${version}`)
		: fail(`the server says Playwright ${version}; the record says ${record.playwright[0]}`);
	server.stdin.write(JSON.stringify({ jsonrpc: "2.0", method: "notifications/initialized" }) + "\n");

	const tools = (await rpc("tools/list", {})).result.tools.map((t) => t.name);
	// A sample of the tools the runner's filter passes (held by
	// agentry-cli), the testing and PDF ones included: a server bump that
	// renames one fails here first.
	const want = ["browser_navigate", "browser_snapshot", "browser_click", "browser_type", "browser_fill_form",
		"browser_take_screenshot", "browser_evaluate", "browser_network_requests", "browser_console_messages",
		"browser_verify_text_visible", "browser_verify_element_visible", "browser_generate_locator", "browser_pdf_save"];
	const missing = want.filter((t) => !tools.includes(t));
	missing.length === 0
		? ok(`tools/list holds the ${want.length} tools the runner's filter passes first (${tools.length} in all)`)
		: fail(`tools/list lacks ${missing.join(", ")}`);

	if (!control) {
		let r = await call("browser_navigate", { url: "http://localhost:8080/" });
		!r.isError && r.text.includes("Agentry browser check")
			? ok("the fixture page renders (its title is in the result)")
			: fail(`navigate to the fixture: ${r.text.slice(0, 400)}`);

		// The user agent string is reduced to 155.0.0.0; the full version
		// is a high-entropy client hint.
		r = await call("browser_evaluate", {
			function: "async () => (await navigator.userAgentData.getHighEntropyValues(['uaFullVersion'])).uaFullVersion",
		});
		r.text.includes(`"${record.chromium[1]}"`)
			? ok(`the browser that runs is Chrome ${record.chromium[1]}, the record's`)
			: fail(`the browser does not report Chrome ${record.chromium[1]}: ${r.text.slice(0, 300)}`);

		r = await call("browser_verify_text_visible", { text: "Fixture page" });
		!r.isError ? ok("browser_verify_text_visible finds the heading") : fail(`verify text: ${r.text.slice(0, 300)}`);

		r = await call("browser_take_screenshot", { filename: "check.png", fullPage: true });
		const png = join(out, "check.png");
		!r.isError && existsSync(png) && readFileSync(png).subarray(1, 4).toString() === "PNG"
			? ok("a screenshot with a chosen name lands in /out-browser as a PNG")
			: fail(`screenshot: ${r.text.slice(0, 300)}`);

		r = await call("browser_pdf_save", { filename: "check.pdf" });
		const pdf = join(out, "check.pdf");
		!r.isError && existsSync(pdf) && readFileSync(pdf).subarray(0, 5).toString() === "%PDF-"
			? ok("browser_pdf_save writes a PDF to /out-browser")
			: fail(`pdf: ${r.text.slice(0, 300)}`);

		r = await call("browser_take_screenshot", { filename: "/etc/escape.png" });
		r.isError ? ok("a file name outside /out-browser is refused") : fail("a screenshot to /etc/escape.png was not refused");

		// The model passes a secret's name; the server types its value and
		// never returns it.
		r = await call("browser_type", { element: "the user field", target: "#user", text: secretName });
		const typed = r;
		r = await call("browser_evaluate", { function: "() => document.querySelector('#user').value" });
		const all = typed.text + r.text;
		!typed.isError && !r.isError && r.text.includes(`<secret>${secretName}</secret>`) && !all.includes(secretValue)
			? ok("a secret typed by name reaches the field, and its value is masked in every result")
			: fail(`secret typing: ${all.slice(0, 400)}`);
	}

	await call("browser_navigate", { url: "https://probe.test:8443/" });
	const h = hellos[0];
	if (!h) {
		fail("the TLS listener saw no ClientHello");
	} else if (h.sni !== "probe.test") {
		fail(`the ClientHello names ${JSON.stringify(h.sni)}, not probe.test`);
	} else if (control) {
		h.ech
			? ok("control: with the policy hidden, Chromium offers ECH, and the listener sees it")
			: fail("control: with the policy hidden, Chromium did not offer ECH, so the check proves nothing");
	} else {
		!h.ech
			? ok("the ClientHello names its host and offers no ECH (the policy is read)")
			: fail("the ClientHello offers ECH: the policy at /etc/opt/chrome_for_testing/policies/managed/ is not read");
	}
} catch (e) {
	fail(String(e.message || e));
}
server.kill();
web.close();
tls.close();
process.exit(failed ? 1 : 0);
