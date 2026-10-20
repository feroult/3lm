#!/usr/bin/env python3
"""Measures generation/prefill speed of an OpenAI-compatible server (llama-server/llama-swap) with real code context.

Usage:  python3 bench/bench.py PORT MODEL LABEL OUTPUT.json
        LINES=2600 python3 bench/bench.py 8000 coder my-test /tmp/res.json     (~21k-token context)

- Uses the first LINES lines of the standard library's `argparse` module as context (700 lines ~ 5.8k tokens;
  2600 ~ 21k tokens), temperature 0, and 4 tasks (2 code edits, 1 from-scratch generation, 1 explanation).
- The first request (WARM) pays the context prefill; the others reuse the prefix (prompt cache).
- Prints generation t/s, newly processed tokens, draft acceptance (if speculative decoding is on) and a short hash of
  the output; the output JSON lets you compare outputs across configurations (temperature 0 does not guarantee
  identical outputs with speculative decoding or a different -ub).
- Note: the numbers in docs/BENCHMARKS.md were measured with equivalent Portuguese-language prompts.
"""
import argparse as _argparse
import hashlib
import json
import os
import sys
import urllib.request

port, model, label, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
host = os.environ.get("HOST", "host.containers.internal")  # use HOST=localhost outside a container
src = open(_argparse.__file__).read().splitlines()
code = "\n".join(src[0:int(os.environ.get("LINES", "700"))])


def req(prompt, max_tokens=300):
    body = json.dumps({"model": model, "temperature": 0, "max_tokens": max_tokens,
                       "messages": [{"role": "user", "content": code + "\n\n" + prompt}]}).encode()
    r = urllib.request.Request(f"http://{host}:{port}/v1/chat/completions", body, {"Content-Type": "application/json"})
    d = json.load(urllib.request.urlopen(r, timeout=900))
    t, m = d["timings"], d["choices"][0]["message"]
    txt = (m.get("content") or "") + "|" + (m.get("reasoning_content") or "")
    return t, hashlib.md5(txt.encode()).hexdigest()[:8]


tasks = [
    ("WARM (context prefill)", "Reply with just: ok", 8),
    ("edit: type hints", "Rewrite the first 40 lines of code above (after the docstring) adding type hints and short docstrings, keeping the logic identical. Show only the rewritten code.", 300),
    ("from scratch (Go)", "Ignore the code above. Write a Go HTTP server with a /health endpoint and graceful shutdown.", 300),
    ("explanation", "Explain in 10 lines what the ArgumentParser class does in this file.", 300),
    ("edit: rename", "Copy the _get_action_name function from the code above, renaming it to get_action_label and translating all comments to Portuguese. Show only the function.", 250),
]
res, gens = [], []
for name, prompt, max_tokens in tasks:
    t, h = req(prompt, max_tokens)
    drafted, accepted = t.get("draft_n", 0), t.get("draft_n_accepted", 0)
    if name.startswith("WARM"):
        print(f"  [{label}] context={t['prompt_n'] + t.get('cache_n', 0)} tok | prefill {t['prompt_per_second']:.0f} t/s ({t['prompt_ms'] / 1000:.1f}s)", flush=True)
    else:
        gens.append(t["predicted_per_second"])
        print(f"  [{label}] {name:26s} gen {t['predicted_per_second']:5.1f} t/s | new={t['prompt_n']:4d} | accepted {accepted}/{drafted} | md5 {h}", flush=True)
        res.append({"task": name, "gen": t["predicted_per_second"], "md5": h})
json.dump(res, open(out, "w"))
print(f"AVERAGE [{label}] generation: {sum(gens) / len(gens):.1f} t/s", flush=True)
