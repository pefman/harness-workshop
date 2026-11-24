#!/usr/bin/env bash
# config/llama.sh — pinned llama.cpp binary manifest.
# Sourced by bin/llama-setup.sh. Two assets, both needed:
#   LLAMA_CPP_BIN_URL    — llama.cpp executables + ggml libs (no CUDA runtime)
#   LLAMA_CPP_CUDART_URL — CUDA runtime (libcudart/libcublas/libcublasLt)
# Do not edit by hand; bump build id here to pin a new release.

LLAMA_CPP_BUILD_ID="b12675"

LLAMA_CPP_BIN_URL="https://github.com/ggml-org/llama.cpp/releases/download/b12675/llama-b12675-bin-ubuntu-cuda-12.8-x64.tar.gz"
LLAMA_CPP_BIN_SIZE_BYTES="220261389"

LLAMA_CPP_CUDART_URL="https://github.com/ggml-org/llama.cpp/releases/download/b12675/cudart-llama-b12675-bin-ubuntu-cuda-12.8-x64.tar.gz"
LLAMA_CPP_CUDART_SIZE_BYTES="594372523"
