# Measured benchmarks

Hardware: RTX 5070 Ti 16GB (Blackwell, PCIe 5.0), DDR5-6000, WSL2 + podman, llama.cpp build 11723 (`server-cuda`).
Almost everything was measured **during a Google Meet call**, which uses the GPU/CPU: run-to-run noise reached ~4 t/s
(the same configuration gave 36.7 and 40.7 t/s). Treat differences of 1-2 t/s as ties. "Total" VRAM includes ~1-2GB used by Windows.
Measurements use `bench/bench.py` (temperature 0, real code context, prefix reused across tasks); the numbers below were
taken with Portuguese-language prompts of equivalent content to the English ones now in the script.

## Current default: Qwen3.6-35B-A3B (MoE) UD-Q6_K + MTP, 64k context

| Configuration | Generation | Prefill | Total VRAM |
|---|---|---|---|
| No MTP, `N_CPU_MOE=30`, `-ub 1024` | ~40 t/s | ~650-700 t/s | ~13.0 GB |
| MTP 2 tokens, `N_CPU_MOE=30` | 52.0 | ~690 | 14.0 GB |
| MTP 3 tokens, `N_CPU_MOE=30` | 53.9 | ~696 | 13.9 GB |
| MTP 2 tokens, `N_CPU_MOE=32` | 50.1 | 675 | 12.6 GB |
| **MTP 3 tokens, `N_CPU_MOE=32`, `-ub 2048` (default)** | **49-52** | **960-1183** | **13.0-13.3 GB** |

- 21k-token context: baseline 39.6 t/s; MTP 51.1 t/s (the MTP gain holds).
- MTP draft acceptance: 86-99%. With temperature 0 the outputs differ from the baseline on ~3 of 4 prompts (common with
  speculative decoding / a different `-ub`); quality was **not** evaluated, only speed.
- Tool calling (`tool_calls`) validated with MTP on.
- Real use (opencode), before MTP: 40.3 t/s generation measured on the server with 14-21k tokens of context;
  most agent steps reprocess only 20-50 tokens (the prefix is reused).

`N_CPU_MOE` (no MTP, short prompt): 36 -> ~38 t/s / 7.4GB; 30 -> ~44-45 / ~11.2GB; 24 -> ~49 / 14.9GB (~1.5 t/s per GB of VRAM).
128k context with all experts on the CPU (`N_CPU_MOE=40`): ~31 t/s, ~5.6GB of VRAM.

### Tested without gain (no-MTP model)
- f16 KV cache: same. 24 threads: 19 t/s (worse; `-t 12` is best). `-tb 16` alone: same (41 t/s).
  `--prio 2` fails inside the container (Permission denied).
- n-gram (`--spec-type ngram-mod`): 32.8 t/s (worse; 3-41% acceptance). `ngram-map-k`: same as baseline. (On the dense 27B,
  `ngram-mod` doubled generation on code edits: 15.5 -> 36.9 t/s; see `experiments/draft/RESULTS.md`.)
- GPU expert cache (`--moe-cache-mib 5632` with `N_CPU_MOE=40`): 37-47 t/s (tie with baseline), ~0.8GB less VRAM, lower prefill.
- `--fit-target` has no effect when `-ngl` is fixed (`--fit` only adjusts what was not set).

## Other models

| Model | Config | Generation | VRAM / headroom |
|---|---|---|---|
| Qwen3.8-27B dense (UD-IQ4_XS) | 100% on GPU, 24k ctx, q8 KV | 46 t/s; prefill ~1600 | ~15.5GB (no headroom) |
| same, 32k ctx q8 KV | overflows VRAM | ~5 t/s | - |
| same, hybrid (`-ngl 55`, 32k ctx) | 10 layers on CPU | ~15 t/s; prefill ~1100 | ~14.3GB (~2GB free) |
| same, `-ngl 52` / `-ngl 40` | 13 / 24 layers on CPU | 13 / 8 t/s | 13.8 / 11.0GB |
| Qwen3.8-Flash-Next (MoE ~125B, UD-IQ3_XXS, 82GB) | `--fit on`, 6GB headroom, 64k ctx | ~25 t/s; prefill ~300 | ~10.1GB |
| Qwen3-Coder-30B-A3B Q4_K_M | CPU only, 16 threads | ~24-26 t/s | ~19GB of RAM |
| Qwen3.8-27B dense | CPU only | ~3 t/s | impractical (memory bandwidth) |

- Dense models lose a lot when layers move to the CPU (each layer = ~0.22GB and ~1-2 t/s); MoE models lose little.
- MTP on the hybrid dense 27B made things **worse** (15.4 -> 4.6-4.9 t/s), as did a small draft model: verifying several
  tokens through the CPU-resident layers is expensive. This differs from the MoE above, where MTP helped.
- Context: the 27B has one attention layer out of every four (recurrent hybrid), so the KV cache is small (~1GB per 32k at q8).

## Not verified
- Answer quality across configurations (speed only).
- Full 64k context with MTP (tested up to ~21k tokens).
- Numbers without the Meet call; `podman-compose`; a cold build; Cursor/Continue/Aider.
