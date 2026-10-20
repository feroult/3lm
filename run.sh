#!/usr/bin/env bash
# Starts the container (podman or docker). Usage: ./run.sh [--cpu|--gpu] [build|start|stop|logs|status]
#   ./run.sh                    GPU, container "coder-llm", host port 8080
#   ./run.sh --cpu              CPU, container "coder-llm-cpu", host port 8081 (no GPU flags; works on machines without a GPU)
#   DEVICE=cpu ./run.sh         same as --cpu
# e.g.: MODEL=qwen3.8-flash-next ./run.sh     HF_TOKEN=hf_xxx API_KEY=secret ./run.sh
#       THREADS=12 MLOCK=1 ./run.sh --cpu     HOST_PORT=8000 ./run.sh   (if host port 8080 is taken)
set -euo pipefail
cd "$(dirname "$0")"
DEVICE="${DEVICE:-gpu}"; cmd=""
for a in "$@"; do
  case "$a" in
    --cpu) DEVICE=cpu;; --gpu) DEVICE=gpu;;
    build|start|stop|logs|status) cmd="$a";;
    *) echo "usage: $0 [--cpu|--gpu] [build|start|stop|logs|status]"; exit 2;;
  esac
done
cmd="${cmd:-start}"
ENGINE="${ENGINE:-$(command -v podman >/dev/null && echo podman || echo docker)}"
IMAGE="${IMAGE:-coder-llm:latest}"; VOLUME="${VOLUME:-llm-models}"
if [[ "$DEVICE" == "cpu" ]]; then NAME="${NAME:-coder-llm-cpu}"; HOST_PORT="${HOST_PORT:-8081}"
else NAME="${NAME:-coder-llm}"; HOST_PORT="${HOST_PORT:-8080}"; fi
case "$cmd" in
  build)  exec $ENGINE build --format docker -t "$IMAGE" . ;;
  stop)   exec $ENGINE rm -f "$NAME" ;;
  logs)   exec $ENGINE logs -f "$NAME" ;;
  status) $ENGINE ps -a --filter "name=^${NAME}$"; exec $ENGINE exec "$NAME" curl -fsS http://127.0.0.1:8080/health ;;
esac
$ENGINE image exists "$IMAGE" 2>/dev/null || $ENGINE image inspect "$IMAGE" >/dev/null 2>&1 || $ENGINE build --format docker -t "$IMAGE" .
$ENGINE rm -f "$NAME" >/dev/null 2>&1 || true

if [[ "$DEVICE" == "cpu" ]]; then
  GPU_FLAGS=""   # CPU mode: no GPU flags
else
  # GPU: WSL2 exposes the GPU through /dev/dxg + libs in /usr/lib/wsl (verified empirically here; CDI does not exist on this host).
  # On native Linux with the NVIDIA Container Toolkit use: GPU_FLAGS="--device nvidia.com/gpu=all" (or --gpus all on docker).
  GPU_FLAGS="${GPU_FLAGS:---device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib}"
fi
ENVS=(-e "DEVICE=$DEVICE")
for v in MODEL CTX_SIZE N_CPU_MOE N_GPU_LAYERS SPEC_N_MAX FIT_TARGET API_KEY HF_TOKEN PRELOAD EXTRA_ARGS THREADS MLOCK NO_MMAP; do
  [[ -n "${!v:-}" ]] && ENVS+=(-e "$v=${!v}")
done
# shellcheck disable=SC2086
exec $ENGINE run -d --name "$NAME" --restart unless-stopped \
  $GPU_FLAGS "${ENVS[@]}" -e PORT=8080 \
  -p "${HOST_PORT}:8080" -v "$VOLUME:/models" \
  --shm-size 1g ${RUN_FLAGS:-} "$IMAGE"
