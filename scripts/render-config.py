#!/usr/bin/env python3
"""Renders /etc/coder/models.yaml -> /run/coder/config.yaml, replacing {{VAR:default}} with environment variables."""
import os, re, sys, yaml
src, dst = sys.argv[1], sys.argv[2]
txt = open(src).read()
txt = re.sub(r"\{\{(\w+):([^}]*)\}\}", lambda m: os.environ.get(m.group(1)) or m.group(2), txt)
cfg = yaml.safe_load(txt)
model = os.environ.get("MODEL") or ("qwen3-coder-30b-a3b-cpu" if os.environ.get("DEVICE") == "cpu" else "qwen3.6-35b-a3b-64k")
names = set(cfg["models"])
for k, v in cfg["models"].items():
    for a in v.get("aliases", []):
        if a == model:
            model = k
if model not in names:
    sys.exit(f"MODEL='{model}' unknown. Available: {', '.join(sorted(names))}")
# the chosen MODEL becomes the default model: the "default"/"coder" aliases point to it
for k, v in cfg["models"].items():
    al = [a for a in v.get("aliases", []) if a not in ("coder", "default", "gpt-4o", "gpt-4")]
    if k == model:
        al += ["coder", "default", "gpt-4o", "gpt-4"]
    if al: v["aliases"] = al
    else: v.pop("aliases", None)
if os.environ.get("API_KEY"):
    cfg["apiKeys"] = [os.environ["API_KEY"]]
if os.environ.get("PRELOAD", "1") != "0":
    cfg["hooks"] = {"on_startup": {"preload": [model]}}
yaml.safe_dump(cfg, open(dst, "w"), sort_keys=False, width=100000)
print(f"[entrypoint] default model: {model}")
