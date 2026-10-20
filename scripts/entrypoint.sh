#!/usr/bin/env bash
# Variables: DEVICE (gpu|cpu), MODEL, CTX_SIZE, N_CPU_MOE, PORT (8080), API_KEY, HF_TOKEN, PRELOAD (1), EXTRA_ARGS,
#            THREADS (cpu only; default = physical cores), MLOCK=1, NO_MMAP=1 (cpu only)
set -euo pipefail
export PORT="${PORT:-8080}"
export DEVICE="${DEVICE:-gpu}"
if [[ "${1:-}" == "list" ]]; then grep -E '^  "' /etc/coder/models.yaml | tr -d '":{' ; exit 0; fi
if [[ $# -gt 0 && "$1" != "serve" ]]; then exec "$@"; fi

if [[ "$DEVICE" == "cpu" ]]; then
  # CPU mode: no CUDA. Hide the GPUs, set -ngl 0 and keep the KV cache in RAM (these args go at the end of the command line and override the model's).
  export CUDA_VISIBLE_DEVICES=-1 NVIDIA_VISIBLE_DEVICES=none GGML_CUDA_NO_PINNED=1
  export MODEL="${MODEL:-qwen3-coder-30b-a3b-cpu}"
  if [[ -z "${THREADS:-}" ]]; then
    # PHYSICAL cores (nproc counts SMT threads). Respects the container's cpuset/--cpus limit.
    phys=$(lscpu -p=CORE,SOCKET 2>/dev/null | grep -v '^#' | sort -u | wc -l || true)
    avail=$(nproc)
    [[ "${phys:-0}" -ge 1 ]] || phys=$avail
    THREADS=$(( phys < avail ? phys : avail ))
  fi
  export THREADS
  cpu_flags="-ngl 0 --no-kv-offload -t ${THREADS} -tb ${THREADS}"
  # newer llama.cpp: --mlock/--no-mmap became --load-mode (mmap+mlock | none | auto)
  if [[ "${MLOCK:-0}" == "1" ]]; then cpu_flags+=" --load-mode mmap+mlock"
  elif [[ "${NO_MMAP:-0}" == "1" ]]; then cpu_flags+=" --load-mode none"; fi
  export EXTRA_ARGS="${cpu_flags} ${EXTRA_ARGS:-}"
  echo "[entrypoint] DEVICE=cpu threads=${THREADS} (visible logical CPUs: $(nproc)) flags: ${EXTRA_ARGS}"
else
  export MODEL="${MODEL:-qwen3.6-35b-a3b-64k}"
  echo "[entrypoint] DEVICE=gpu; GPU:"
  (nvidia-smi -L 2>/dev/null || /usr/lib/wsl/lib/nvidia-smi -L 2>/dev/null || echo "  nvidia-smi unavailable (check the llama-server logs for CUDA)")
fi
render-config.py /etc/coder/models.yaml /run/coder/config.yaml
exec llama-swap -config /run/coder/config.yaml -listen "0.0.0.0:${PORT}"
