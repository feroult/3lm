# coder-llm: a local coding LLM with an OpenAI-compatible API

A single container (llama.cpp + llama-swap, CUDA 12.8 with Blackwell sm_120 kernels) that serves `/v1/chat/completions`,
`/v1/models` and `/health` (port 8080 inside the container). Built for an **RTX 5070 Ti 16GB + 96GB DDR5 (WSL2 + podman)**,
leaving spare GPU memory for calls and other uses. It also runs on CPU only.

**Default (GPU):** `qwen3.6-35b-a3b-64k` = Qwen3.6-35B-A3B (MoE, 3B active) `UD-Q6_K` **with MTP**, 64k context, experts
in RAM and attention/KV cache on the GPU: **~50 t/s** generation, ~1000-1200 t/s prefill, ~13GB of total VRAM (~3GB free).
The other models are optional: ask for them by name in the `model` field (downloaded on first use) or set `MODEL=`.
Measurements and what did not help: [`docs/BENCHMARKS.md`](docs/BENCHMARKS.md).

## Quick start

```bash
./run.sh build                    # build the image (uses --format docker so the HEALTHCHECK is kept)
HOST_PORT=8000 ./run.sh           # start "coder-llm" (the first start downloads ~30GB into the llm-models volume)
./run.sh logs                     # follow the logs; ./run.sh stop removes the container
./test.sh http://localhost:8000   # health, models, chat, streaming, tool call, code (or EXEC_CONTAINER=coder-llm ./test.sh)
./run.sh --cpu                    # CPU mode: container "coder-llm-cpu", port 8081, no GPU
```

Default `HOST_PORT`: 8080 (GPU) and 8081 (CPU); use `HOST_PORT=8000` if 8080 is taken by something else
(on the author's machine it is the [swarmbox](https://github.com/feroult/swarmbox) sandbox).
`podman-compose` should also work (`compose.yaml`; the `cpu` profile starts CPU mode) but it was only validated as YAML.

## Clients

Endpoint `http://localhost:8000/v1` (or your `HOST_PORT`; from inside another container use
`http://host.containers.internal:8000/v1`). Any `api_key`, or the value of `API_KEY`. Model: `qwen3.6-35b-a3b-64k`
(or the aliases `coder`, `default`, `gpt-4o`).

- **opencode** (`~/.config/opencode/opencode.json`; the right key is `provider`, singular, with `npm` and `options`).
  This is how it is wired up for the [swarmbox](https://github.com/feroult/swarmbox) sandbox, where opencode runs:
  ```json
  {
    "$schema": "https://opencode.ai/config.json",
    "provider": { "local": {
      "npm": "@ai-sdk/openai-compatible", "name": "llama.cpp local",
      "options": { "baseURL": "http://host.containers.internal:8000/v1", "apiKey": "sk-local" },
      "models": { "qwen3.6-35b-a3b-64k": { "name": "qwen3.6-35b-a3b-64k", "limit": { "context": 65536, "output": 8192 } } }
    } },
    "model": "local/qwen3.6-35b-a3b-64k"
  }
  ```
- **Aider**: `OPENAI_API_BASE=http://localhost:8000/v1 OPENAI_API_KEY=sk-local aider --model openai/coder`
- **openai SDK**: `OpenAI(base_url="http://localhost:8000/v1", api_key="sk-local")` (example in `examples/openai_example.py`)
- **curl**: `curl localhost:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"coder","messages":[{"role":"user","content":"hi"}]}'`

## Models (`models.yaml`)

Only one model is loaded at a time; llama-swap swaps when you request another one (seconds to minutes).

| name | file | notes |
|---|---|---|
| `qwen3.6-35b-a3b-64k` (**GPU default**) | UD-Q6_K + MTP, 30GB | ~50 t/s, 64k, ~13GB of VRAM (~3GB free), `-np 1` (required by MTP) |
| `qwen3.6-35b-a3b-64k-nomtp` | UD-Q6_K, 29GB | the same model without MTP, ~40 t/s; fallback if MTP causes problems |
| `qwen3.8-27b` | UD-IQ4_XS, 14.3GB | dense, 100% in VRAM, 24k ctx, ~46 t/s, **uses the whole card** |
| `qwen3.8-27b-hybrid` | same | 10 layers on CPU, 32k ctx, ~15 t/s, ~2GB of VRAM free (`N_GPU_LAYERS`) |
| `qwen3.8-27b-instant` / `-q4km` | same / 16.5GB | no thinking / slightly higher quality (partly in RAM) |
| `qwen3.8-flash-next` | UD-IQ3_XXS, 82GB | ~125B MoE, experts in RAM, 64k ctx, ~25 t/s, ~6GB of VRAM free; needs `memory>=90GB` in `.wslconfig` |
| `qwen3.6-35b-a3b` | UD-Q4_K_M, 22GB | MoE with partial experts in RAM (not measured) |
| `gpt-oss-20b` | MXFP4, 12GB | light (not measured) |
| `smoke` | Qwen3-0.6B, 0.4GB | plumbing test |

To give WSL2 more RAM: `C:\Users\<you>\.wslconfig` with `[wsl2]` `memory=88GB` `swap=16GB`, then `wsl --shutdown`.

## Environment variables

| Variable | Default | Purpose |
|---|---|---|
| `MODEL` | `qwen3.6-35b-a3b-64k` (GPU) / `qwen3-coder-30b-a3b-cpu` (CPU) | preloaded model and target of the `coder`/`default`/`gpt-4o` aliases |
| `CTX_SIZE` | per model (65536 for the default) | context (`-c`); beyond what fits in VRAM, speed collapses |
| `N_CPU_MOE` | 32 | MoE layers whose experts stay in RAM (lower = more VRAM and more speed; ~1.5 t/s per GB) |
| `SPEC_N_MAX` | 3 | MTP draft tokens |
| `N_GPU_LAYERS` | 55 | `qwen3.8-27b-hybrid` only |
| `THREADS` | 12 (GPU) / physical cores (CPU) | threads; more than ~12 hurts (24 threads: 19 t/s) |
| `FIT_TARGET` | per model | VRAM headroom in MiB (models using `--fit on`, e.g. flash-next: 6144) |
| `DEVICE` | `gpu` | `cpu` = CPU mode (same as `./run.sh --cpu`) |
| `MLOCK` / `NO_MMAP` | empty | CPU only: `--load-mode mmap+mlock` / `--load-mode none` (newer llama.cpp removed `--mlock`/`--no-mmap`) |
| `HOST_PORT` / `PORT` | 8080 (GPU), 8081 (CPU) / 8080 | host port / internal port (`CPU_HOST_PORT` in compose) |
| `API_KEY` | empty | require `Authorization: Bearer` |
| `HF_TOKEN` | empty | Hugging Face token (optional) |
| `PRELOAD` | 1 | `0` = load only on the first request |
| `EXTRA_ARGS` | empty | extra llama-server flags (they go last; the last one wins) |

The `{{VAR:default}}` values in `models.yaml` are replaced by these variables at startup (`scripts/render-config.py`).

## CPU mode (no GPU)

```bash
./run.sh --cpu                       # container coder-llm-cpu on http://localhost:8081
THREADS=12 MLOCK=1 ./run.sh --cpu
MODEL=qwen3.6-35b-a3b-cpu ./run.sh --cpu
```

Same image: with `DEVICE=cpu` the entrypoint sets `CUDA_VISIBLE_DEVICES=-1`, `-ngl 0`, `--no-kv-offload`, and `run.sh` passes
no GPU flags to podman. Default: `qwen3-coder-30b-a3b-cpu` (MoE, Q4_K_M, ~19GB of RAM): **~24-26 t/s**. The KV cache stays in f16
(`q8_0` made long prefill ~4x slower). A dense 27B on CPU gives ~3 t/s (impractical: generation is bound by RAM bandwidth).
To limit the CPU you use (e.g. gaming at the same time), lower `THREADS` and set the affinity of the `vmmemWSL` process on Windows (Process Lasso).

## GPU on WSL2 + podman

`--device /dev/dxg -v /usr/lib/wsl:/usr/lib/wsl:ro -e LD_LIBRARY_PATH=/usr/lib/wsl/lib` (CDI `nvidia.com/gpu=all` does not exist in this setup).
On native Linux: `GPU_FLAGS="--device nvidia.com/gpu=all" ./run.sh`. Available VRAM is the card's minus whatever Windows uses (1-2GB,
plus whatever a call/game uses); if it runs short the driver starts paging and generation drops from ~50 to ~5 t/s. If that happens,
raise `N_CPU_MOE` or lower `CTX_SIZE`.

## Layout

```
Dockerfile, compose.yaml, run.sh     image, compose file and launcher (GPU/CPU)
models.yaml                          model catalog (llama-swap format) with the measured flags
scripts/                             entrypoint, serve-model.sh (resumable download), render-config.py
test.sh, examples/                   API validation and an openai-SDK example
bench/bench.py                       benchmark with real code context (generation, prefill, acceptance)
docs/BENCHMARKS.md                   measured results and what did not work
experiments/draft/                   draft-model / n-gram experiments on the 27B (results and scripts)
```

## Known issues / not verified

- The `HEALTHCHECK` turns `healthy` as soon as llama-swap is up, **before** the model has loaded (the first request waits for the load).
- The log does not print "offloaded N/N layers"; check the GPU with `nvidia-smi` (inside the container: `/usr/lib/wsl/lib/nvidia-smi`).
- `--prio` fails inside the container (Permission denied) and `--fit-target` has no effect with a fixed `-ngl`.
- Not verified: answer quality across configurations (speed only), full 64k context with MTP (tested up to ~21k),
  `podman-compose` (YAML only), a cold build, downloading the MTP GGUF on a clean machine (`serve-model.sh` accepts `FILE=LOCAL_NAME`),
  `qwen3.6-35b-a3b`, `gpt-oss-20b`, `qwen3.6-35b-a3b-cpu`, and the Cursor/Continue/Aider clients.
- Measurements were taken during a Google Meet call; differences of 1-2 t/s are within the noise.

## Licenses

The models are downloaded from Hugging Face at first use and keep their own licenses (e.g. Qwen models; Flash-Next is listed as "other").
This repository does not redistribute any model weights.

## Pushing to a remote

The repository is initialized on branch `main` and committed locally. To publish it:

```bash
git remote add origin <YOUR-REPOSITORY-URL>
git push -u origin main
```

Model weights (`*.gguf`) live in the `llm-models` podman volume, not in the repository (see `.gitignore`).
