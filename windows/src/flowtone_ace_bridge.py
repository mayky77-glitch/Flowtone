import argparse
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import time
import urllib.parse
import urllib.request


def request_json(url, payload=None, timeout=30):
    body = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {} if body is None else {"Content-Type": "application/json"}
    request = urllib.request.Request(url, data=body, headers=headers)
    with urllib.request.urlopen(request, timeout=timeout) as response:
        value = json.loads(response.read().decode("utf-8"))
    if value.get("code") not in (None, 200):
        raise RuntimeError(value.get("error") or "ACE-Step API error")
    return value


parser = argparse.ArgumentParser(description="Flowtone ACE-Step bridge")
parser.add_argument("--prompt")
parser.add_argument("--negative-prompt", default="")
parser.add_argument("--model", default="acestep-v15-turbo")
parser.add_argument("--lm", default="none")
parser.add_argument("--seconds", type=int, default=120)
parser.add_argument("--steps", type=int, default=8)
parser.add_argument("--seed", type=int, default=0)
parser.add_argument("--out")
args = parser.parse_args()
if not args.prompt or not args.out:
    parser.error("--prompt and --out are required")

with socket.socket() as probe:
    probe.bind(("127.0.0.1", 0))
    port = probe.getsockname()[1]
base = f"http://127.0.0.1:{port}"
env = os.environ.copy()
env["ACESTEP_CONFIG_PATH"] = args.model
env["ACESTEP_INIT_LLM"] = "false" if args.lm == "none" else "true"
if args.lm != "none":
    env["ACESTEP_LM_MODEL_PATH"] = args.lm
env["ACESTEP_API_HOST"] = "127.0.0.1"
env["ACESTEP_API_PORT"] = str(port)
env["TOKENIZERS_PARALLELISM"] = "false"
log_path = os.path.join(os.getcwd(), "flowtone-api.log")
log = open(log_path, "ab", buffering=0)
server = subprocess.Popen(
    [sys.executable, "-m", "acestep.api_server", "--host", "127.0.0.1", "--port", str(port)],
    cwd=os.getcwd(),
    env=env,
    stdin=subprocess.DEVNULL,
    stdout=log,
    stderr=log,
    creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
)


def stop_server(*_):
    if server.poll() is None:
        server.terminate()
        try:
            server.wait(timeout=15)
        except subprocess.TimeoutExpired:
            server.kill()
    log.close()


signal.signal(signal.SIGTERM, lambda *_: (stop_server(), sys.exit(143)))
signal.signal(signal.SIGINT, lambda *_: (stop_server(), sys.exit(130)))
try:
    deadline = time.monotonic() + 900
    while True:
        if server.poll() is not None:
            raise RuntimeError(f"ACE-Step API stopped during startup; see {log_path}")
        try:
            request_json(base + "/health", timeout=5)
            break
        except Exception:
            if time.monotonic() >= deadline:
                raise RuntimeError(f"ACE-Step API startup timeout; see {log_path}")
            time.sleep(2)

    payload = {
        "prompt": args.prompt,
        "negative_prompt": args.negative_prompt,
        "lyrics": "[Instrumental]",
        "thinking": args.lm != "none",
        "model": args.model,
        "audio_duration": max(10, min(args.seconds, 120)),
        "audio_format": "wav",
        "inference_steps": max(1, args.steps),
        "seed": args.seed,
    }
    created = request_json(base + "/release_task", payload, timeout=60)
    task_id = created["data"]["task_id"]
    deadline = time.monotonic() + 10800
    while True:
        state = request_json(base + "/query_result", {"task_id_list": [task_id]}, timeout=30)
        item = state["data"][0]
        if int(item.get("status", 0)) == 2:
            raise RuntimeError(item.get("error") or "ACE-Step generation failed")
        if int(item.get("status", 0)) == 1:
            results = json.loads(item["result"])
            audio_path = results[0]["file"]
            break
        if time.monotonic() >= deadline:
            raise RuntimeError("ACE-Step generation timeout")
        time.sleep(2)

    part = args.out + ".part"
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    with urllib.request.urlopen(urllib.parse.urljoin(base, audio_path), timeout=600) as response:
        with open(part, "wb") as output:
            shutil.copyfileobj(response, output)
    if os.path.getsize(part) < 44:
        raise RuntimeError("ACE-Step returned an empty audio file")
    os.replace(part, args.out)
    print(args.out)
finally:
    stop_server()
