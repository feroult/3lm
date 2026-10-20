# syntax=docker/dockerfile:1
# coder-llm: llama.cpp (CUDA 12.8+, includes Blackwell sm_120 kernels) + llama-swap
# -> a single OpenAI-compatible API (/v1/chat/completions, /v1/models) serving several models.
#
# Both stages below are official images: llama.cpp "server-cuda" is built with CUDA 12.8.1
# and includes architectures up to 120 (RTX 50xx). To pin versions: --build-arg LLAMA_CPP_TAG=... --build-arg LLAMA_SWAP_TAG=...
ARG LLAMA_CPP_TAG=server-cuda
ARG LLAMA_SWAP_TAG=cuda

FROM ghcr.io/mostlygeek/llama-swap:${LLAMA_SWAP_TAG} AS swap
# we only need the static llama-swap binary

FROM ghcr.io/ggml-org/llama.cpp:${LLAMA_CPP_TAG} AS runtime
ENV DEBIAN_FRONTEND=noninteractive \
    LD_LIBRARY_PATH=/usr/lib/wsl/lib:/app:/usr/local/nvidia/lib64:/usr/local/cuda/lib64 \
    NVIDIA_VISIBLE_DEVICES=all NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    MODELS_DIR=/models

RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates python3 python3-yaml util-linux \
 && rm -rf /var/lib/apt/lists/*

COPY --from=swap /app/llama-swap /usr/local/bin/llama-swap
COPY models.yaml /etc/coder/models.yaml
COPY scripts/entrypoint.sh scripts/serve-model.sh scripts/render-config.py /usr/local/bin/
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/serve-model.sh /usr/local/bin/render-config.py \
 && mkdir -p /models /run/coder && chmod 1777 /models /run/coder

# Rootless podman: "root" in the container is an unprivileged user on the host.
# To run as another uid use --user, as long as the /models volume is writable by it.
VOLUME /models
EXPOSE 8080
ENV PORT=8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-8080}/health" >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
