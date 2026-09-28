"""An OpenAI-compatible chat endpoint answered by the `claude` CLI on this machine.

The supervisor's side of a model call from inside the sandbox. golemide, confined by
porta, cannot run `claude` itself: porta closes the Keychain its login is kept in, which
is the point. aitrium starts this bridge on 127.0.0.1 with a token for the session, and
golemide reaches it through almai's NAME/MODEL route as `claudecli/MODEL`, holding only
the URL and the token:

    python3 bridge/claude_bridge.py --host 127.0.0.1 --port 8789 --token T
    CLAUDECLI_BASE_URL=http://127.0.0.1:8789/v1 CLAUDECLI_API_KEY=T golemide solve … --model claudecli/sonnet

`claudecli/default` leaves the model to claude. (comide's bench/tb2 carries the same
bridge for task containers.)

Each request becomes one `claude -p`: the conversation rendered as text, the tools
described in the system prompt, and the reply one JSON object: the next assistant turn,
words and the tool calls to make. claude runs with no tools at all (--json-schema would
give it one, and it then tries the listed actions as tools of its own, turn after turn),
and in --safe-mode, so neither this machine's CLAUDE.md nor its hooks reach it.
Nothing is kept between requests; the whole conversation is sent every time.
"""

import argparse
import json
import subprocess
import sys
import tempfile
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TURN_RULES = """

---
You are the model behind an agent. You cannot run anything yourself: the agent performs
the actions listed below for you and sends back each one's result, marked
`[result of ID]`. Reply with exactly one JSON object and nothing else, no code fence:

  {"text": "what you say", "tool_calls": [{"name": "ACTION", "arguments": {...}}]}

Your earlier turns appear in the conversation as such objects, each call with an "id"
that its result names; leave "id" out of your own reply.

`tool_calls` holds the actions to perform now, each with its arguments following the
action's parameters. Leave it empty ([]) when you are done or need nothing performed."""

NEXT_TURN = "Write the assistant's next turn: one JSON object, nothing else."


def render_tools(tools):
    lines = ["", "Actions the agent can perform (put them in tool_calls):"]
    for t in tools or []:
        f = t.get("function", t)
        lines.append(f"- {f.get('name')}: {f.get('description', '').strip()}")
        lines.append(f"  parameters: {json.dumps(f.get('parameters', {}), ensure_ascii=False)}")
    return "\n".join(lines)


def content_text(content):
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(p.get("text", "") for p in content if isinstance(p, dict))
    return "" if content is None else str(content)


def render_conversation(messages):
    """The conversation as text. The assistant's own turns are written as the very JSON
    object it is asked to reply with: claude copies the shape of what it sees, and a
    transcript in any other shape comes back as its answer."""
    out = []
    for m in messages:
        role = m.get("role")
        if role == "system":
            continue
        text = content_text(m.get("content"))
        if role == "tool":
            out.append(f"[result of {m.get('tool_call_id', '')}]\n{text}")
        elif role == "assistant":
            calls = []
            for tc in m.get("tool_calls") or []:
                f = tc.get("function", {})
                try:
                    args = json.loads(f.get("arguments") or "{}")
                except json.JSONDecodeError:
                    args = {"_raw": f.get("arguments")}
                calls.append({"id": tc.get("id", ""), "name": f.get("name"), "arguments": args})
            out.append("[assistant]\n" + json.dumps({"text": text, "tool_calls": calls}, ensure_ascii=False))
        else:
            out.append(f"[{role}]\n{text}")
    return "\n\n".join(out) + "\n\n" + NEXT_TURN


def parse_turn(result, required):
    """The JSON object in claude's answer, or None when there is none, or it names an
    action that does not exist or leaves out one of an action's required arguments.
    `required` maps each action's name to its required parameters."""
    start, end = result.find("{"), result.rfind("}")
    if start < 0 or end < start:
        return None
    try:
        turn = json.loads(result[start:end + 1])
    except json.JSONDecodeError:
        return None
    # The reply itself, not an object quoted inside it (a call's arguments, say).
    if not isinstance(turn, dict) or "tool_calls" not in turn or not isinstance(turn["tool_calls"] or [], list):
        return None
    # claude now and then writes the arguments beside the name instead of under
    # "arguments"; both mean the same call.
    calls = [{"name": c.get("name"), "arguments": c["arguments"] if "arguments" in c else {k: v for k, v in c.items() if k not in ("name", "id")}}
             if isinstance(c, dict) else c for c in turn.get("tool_calls") or []]
    for c in calls:
        if not isinstance(c, dict) or c.get("name") not in required or not isinstance(c.get("arguments", {}), dict):
            return None
        if any(c.get("arguments", {}).get(k) in (None, "") for k in required[c["name"]]):
            return None
    return {"text": str(turn.get("text", "")), "tool_calls": calls}


def requested_model(req):
    """The model to pass claude, or "" for its own default (`claudecli/default`)."""
    model = req.get("model", "")
    return "" if model == "default" else model


def forced_tool(choice):
    if isinstance(choice, dict):
        return choice.get("function", {}).get("name")
    return None


def ask_structured(req, schema, workdir, claude, lock_log):
    """A request for an answer in a given shape (response_format json_schema, no tools):
    claude's --json-schema, whose result is the answer's text. With no actions offered
    there is nothing claude could mistake for a tool of its own."""
    messages = req.get("messages", [])
    system = "\n\n".join(content_text(m.get("content")) for m in messages if m.get("role") == "system")
    cmd = [claude, "-p", "--output-format", "json", "--tools", "", "--no-session-persistence", "--safe-mode",
           "--system-prompt", system or "Answer as asked.", "--json-schema", json.dumps(schema)]
    model = requested_model(req)
    if model:
        cmd += ["--model", model]
    convo = "\n\n".join(f"[{m.get('role')}]\n{content_text(m.get('content'))}" for m in messages if m.get("role") != "system")
    started = time.time()
    proc = subprocess.run(cmd, input=convo, capture_output=True, text=True, cwd=workdir, timeout=900)
    try:
        out = json.loads(proc.stdout)
    except json.JSONDecodeError:
        raise RuntimeError(f"claude exited {proc.returncode}: {(proc.stderr or proc.stdout)[-500:]}")
    if out.get("is_error") or out.get("structured_output") is None:
        raise RuntimeError(f"claude: no structured answer: {str(out.get('result'))[:500]}")
    with lock_log:
        print(f"{time.strftime('%H:%M:%S')} {model or 'default'} structured {time.time() - started:.1f}s ${out.get('total_cost_usd', 0):.4f}", flush=True)
    turn = {"text": json.dumps(out["structured_output"], ensure_ascii=False), "tool_calls": []}
    return turn, out.get("usage", {}), out.get("total_cost_usd", 0.0)


def ask_claude(req, workdir, claude, lock_log):
    messages = req.get("messages", [])
    tools = req.get("tools") or []
    fmt = req.get("response_format") or {}
    if fmt.get("type") == "json_schema" and not tools:
        return ask_structured(req, fmt.get("json_schema", {}).get("schema", {}), workdir, claude, lock_log)
    forced = forced_tool(req.get("tool_choice"))
    system = "\n\n".join(content_text(m.get("content")) for m in messages if m.get("role") == "system")
    system += TURN_RULES + render_tools(tools)
    if forced:
        system += f"\n\nThis turn must include the action {forced} in tool_calls."
    cmd = [claude, "-p", "--output-format", "json", "--tools", "", "--no-session-persistence", "--safe-mode",
           "--system-prompt", system]
    model = requested_model(req)
    if model:
        cmd += ["--model", model]
    specs = {t.get("function", t).get("name"): t.get("function", t).get("parameters", {}).get("required", []) for t in tools}
    required = {forced: specs.get(forced, [])} if forced else specs
    started = time.time()
    prompt = render_conversation(messages)
    for attempt in range(3):
        proc = subprocess.run(cmd, input=prompt, capture_output=True, text=True, cwd=workdir, timeout=900)
        try:
            out = json.loads(proc.stdout)
        except json.JSONDecodeError:
            raise RuntimeError(f"claude exited {proc.returncode}: {(proc.stderr or proc.stdout)[-500:]}")
        if out.get("is_error"):
            raise RuntimeError(f"claude: {str(out.get('result'))[:500]}")
        turn = parse_turn(str(out.get("result", "")), required)
        if turn is not None and (not forced or turn["tool_calls"]):
            break
        with lock_log:
            print(f"{time.strftime('%H:%M:%S')} rejected: {str(out.get('result', ''))[:300]!r}", flush=True)
        prompt = render_conversation(messages) + "\n\n(Your last answer was not one JSON object naming only the " \
            "listed actions. " + NEXT_TURN + ")"
    else:
        # An error, not words with no calls: those would read as the agent being done.
        raise RuntimeError("claude did not answer in the agent's format three times")
    took = time.time() - started
    usage = out.get("usage", {})
    with lock_log:
        print(f"{time.strftime('%H:%M:%S')} {model or 'default'} {len(messages)} msgs {took:.1f}s try {attempt + 1} "
              f"calls={[c.get('name') for c in turn.get('tool_calls', [])]} ${out.get('total_cost_usd', 0):.4f}", flush=True)
    return turn, usage, out.get("total_cost_usd", 0.0)


def openai_reply(model, turn, usage, cost):
    calls = [{"id": "call_" + uuid.uuid4().hex[:12], "type": "function",
              "function": {"name": c["name"], "arguments": json.dumps(c.get("arguments", {}), ensure_ascii=False)}}
             for c in turn.get("tool_calls", [])]
    prompt = usage.get("input_tokens", 0) + usage.get("cache_read_input_tokens", 0) + usage.get("cache_creation_input_tokens", 0)
    message = {"role": "assistant", "content": turn.get("text", "")}
    if calls:
        message["tool_calls"] = calls
    return {
        "id": "chatcmpl-" + uuid.uuid4().hex[:12], "object": "chat.completion", "created": int(time.time()), "model": model,
        "choices": [{"index": 0, "message": message, "finish_reason": "tool_calls" if calls else "stop"}],
        "usage": {"prompt_tokens": prompt, "completion_tokens": usage.get("output_tokens", 0),
                  "total_tokens": prompt + usage.get("output_tokens", 0),
                  "prompt_tokens_details": {"cached_tokens": usage.get("cache_read_input_tokens", 0)},
                  "cost": cost},
    }


def stream_chunks(reply):
    """The whole reply as OpenAI stream chunks: the words, the calls, then the finish."""
    base = {k: reply[k] for k in ("id", "created", "model")}
    base["object"] = "chat.completion.chunk"
    msg = reply["choices"][0]["message"]
    delta = {"role": "assistant", "content": msg.get("content", "")}
    if msg.get("tool_calls"):
        delta["tool_calls"] = [dict(tc, index=i) for i, tc in enumerate(msg["tool_calls"])]
    yield {**base, "choices": [{"index": 0, "delta": delta, "finish_reason": None}]}
    yield {**base, "choices": [{"index": 0, "delta": {}, "finish_reason": reply["choices"][0]["finish_reason"]}]}
    yield {**base, "choices": [], "usage": reply["usage"]}


# Seconds between the bytes sent while claude is still thinking.
KEEPALIVE_S = 15


class Handler(BaseHTTPRequestHandler):
    server_version = "claude-bridge"

    def log_message(self, *_):
        pass

    def log_error(self, fmt, *args):
        print(f"{time.strftime('%H:%M:%S')} http error: {fmt % args}", file=sys.stderr, flush=True)

    def send_json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.rstrip("/").endswith("/models"):
            self.send_json(200, {"object": "list", "data": [{"id": m, "object": "model"} for m in ("sonnet", "opus", "haiku")]})
        else:
            self.send_json(404, {"error": {"message": "not found"}})

    def authorised(self):
        """With --token, only a request carrying it: a bridge on a shared machine is
        otherwise anyone's way into the Claude login."""
        token = self.server.token
        return not token or self.headers.get("Authorization", "") == "Bearer " + token

    def do_POST(self):
        if not self.authorised():
            return self.send_json(401, {"error": {"message": "wrong or missing token", "type": "claude_bridge"}})
        if not self.path.rstrip("/").endswith("/chat/completions"):
            return self.send_json(404, {"error": {"message": "not found"}})
        print(f"{time.strftime('%H:%M:%S')} request from {self.client_address[0]}, {self.headers.get('Content-Length')} bytes", flush=True)
        try:
            raw = self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}"
            # strict=False: Almide's json.stringify leaves control characters such as
            # ESC unescaped (almide/almide#2802), and a tool's coloured output carries them.
            req = json.loads(raw, strict=False)
            bad = sorted({hex(b) for b in raw if b < 0x20 and b not in (0x0a, 0x0d)})
            if bad:
                print(f"{time.strftime('%H:%M:%S')} note: raw control bytes in the request: {bad}", flush=True)
        except (ValueError, json.JSONDecodeError) as e:
            return self.send_json(400, {"error": {"message": f"bad request: {e}"}})
        stream = bool(req.get("stream"))
        # claude can think for minutes before its first word, and the agent gives up on a
        # connection that stays silent that long. So the answer starts now: SSE comments
        # while streaming, and otherwise whitespace ahead of the JSON body, which a JSON
        # reader skips. The length is not known yet, so the connection's end marks it.
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream" if stream else "application/json")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "close")
        self.end_headers()
        self.close_connection = True
        result = {}
        worker = threading.Thread(target=self.answer, args=(req, result), daemon=True)
        worker.start()
        # A chunk with nothing in it, not an SSE comment: almai reads a body that does not
        # begin with `data:` as one JSON document (almide-ai/almai#13).
        idle = {"id": "chatcmpl-wait", "object": "chat.completion.chunk", "created": int(time.time()), "model": req.get("model", ""),
                "choices": [{"index": 0, "delta": {}, "finish_reason": None}]}
        while worker.is_alive():
            worker.join(KEEPALIVE_S)
            if worker.is_alive():
                self.wfile.write(f"data: {json.dumps(idle)}\n\n".encode() if stream else b" ")
                self.wfile.flush()
        if "error" in result:
            body = {"error": {"message": result["error"], "type": "claude_bridge"}}
            self.wfile.write((f"data: {json.dumps(body)}\n\n" if stream else json.dumps(body)).encode())
            return
        reply = result["reply"]
        if not stream:
            self.wfile.write(json.dumps(reply).encode())
            return
        for chunk in stream_chunks(reply):
            self.wfile.write(f"data: {json.dumps(chunk)}\n\n".encode())
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()

    def answer(self, req, result):
        try:
            turn, usage, cost = ask_claude(req, self.server.workdir, self.server.claude, self.server.lock)
            result["reply"] = openai_reply(req.get("model", ""), turn, usage, cost)
        except Exception as e:  # the agent sees an error and retries or stops
            print(f"{time.strftime('%H:%M:%S')} error: {e}", file=sys.stderr, flush=True)
            result["error"] = str(e)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--port", type=int, default=8787)
    ap.add_argument("--host", default="0.0.0.0", help="0.0.0.0 so Docker containers reach it via host.docker.internal")
    ap.add_argument("--claude", default="claude")
    ap.add_argument("--token", default="", help="require Authorization: Bearer TOKEN (the caller's *_API_KEY)")
    args = ap.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    server.workdir = tempfile.mkdtemp(prefix="claude-bridge-")
    server.claude = args.claude
    server.token = args.token
    server.lock = threading.Lock()
    print(f"claude bridge on {args.host}:{args.port} (cwd {server.workdir})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
