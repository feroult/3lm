#!/bin/bash
# usage: bench_one.sh "<label>" "<EXTRA_ARGS>"     (run while holding exclusive use of the GPU)
LABEL="$1"; EXTRA="$2"; N=coder-llm-draft; PORT=8101
cd "$(dirname "$0")/../.."
echo "=== $LABEL"; echo "    EXTRA_ARGS: $EXTRA"
NAME=$N HOST_PORT=$PORT MODEL=qwen3.8-27b-hybrid EXTRA_ARGS="$EXTRA" ./run.sh start >/dev/null 2>&1
for i in $(seq 1 90); do [ "$(podman inspect -f '{{.State.Health.Status}}' $N 2>/dev/null)" = healthy ] && break; sleep 2; done
PROMPTSET="$PROMPTSET" python3 -I experiments/draft/measure.py http://host.containers.internal:$PORT qwen3.8-27b-hybrid 2>&1 | tail -8
echo "    total VRAM: $(podman exec $N /usr/lib/wsl/lib/nvidia-smi --query-gpu=memory.used --format=csv,noheader 2>/dev/null)"
podman logs $N 2>&1 | grep -iE "draft|speculative|spec-|accept|not support|error|failed" | grep -v "GET /" | tail -4 | cut -c1-220
podman rm -f $N >/dev/null 2>&1
