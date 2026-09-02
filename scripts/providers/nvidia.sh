#!/bin/bash
# ABOUTME: Queries NVIDIA NIM (build.nvidia.com) via its OpenAI-compatible endpoint
# ABOUTME: Seats DeepSeek V4 Pro on the council — a frontier coding model on a free endpoint

set -euo pipefail

# Source shared libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/retry.sh"
source "$SCRIPT_DIR/../lib/tokens.sh"
source "$SCRIPT_DIR/../lib/verbosity.sh"
source "$SCRIPT_DIR/../lib/providers.sh"

verbosity_prefix VERBOSITY_PREFIX "${COUNCIL_VERBOSITY:-standard}"

# Debug mode
DEBUG="${COUNCIL_DEBUG:-}"

PROMPT="${1:-}"
# A large prompt (e.g. a big --file) arrives via a temp file to stay off the
# process argv, where the OS would reject it as "argument list too long". The
# path is kept, not just the text: jq reads the prompt with --rawfile, so it
# stays off jq's argv too — bounded by the same limit.
PROMPT_FILE=""
if [[ "$PROMPT" == "--prompt-file" ]]; then
    PROMPT_FILE="${2:?--prompt-file requires a path}"
    PROMPT=""
    shift 2
elif [[ $# -gt 0 ]]; then
    shift
fi
# No --image-file branch: provider_vision_capable leaves nvidia out. The default
# model is text-only. kimi-k3 on NIM is multimodal, so if NVIDIA_MODEL is ever
# pointed at it, vision becomes a real option — until then the flag is ignored.
while [[ $# -gt 0 ]]; do shift; done

if [[ -z "$PROMPT" && ! -s "$PROMPT_FILE" ]]; then
    echo "Error: No prompt provided" >&2
    exit 1
fi

# Check for API key. Named NVIDIA_API_KEY because discover_providers derives the
# variable from this file's name. The key is issued at build.nvidia.com and
# carries an nvapi- prefix; it is not a DeepSeek key, which is why this provider
# is named for the host (NVIDIA) and not for the model it happens to serve.
API_KEY="${NVIDIA_API_KEY:-}"
if [[ -z "$API_KEY" ]]; then
    echo "Error: NVIDIA_API_KEY not set" >&2
    exit 1
fi

# Model selection (override via NVIDIA_MODEL env var).
# Verified live on 2026-08-29 against a build.nvidia.com key:
#   deepseek-ai/deepseek-v4-pro-0813   HTTP 200, ~180 s to first byte
#   moonshotai/kimi-k3                 HTTP 200, fast
#   deepseek-ai/deepseek-v4-flash-0731 no bytes in 300 s — do not use
MODEL="$(get_model nvidia)"

# NVIDIA API Catalog endpoint (OpenAI-compatible Chat Completions)
ENDPOINT="${NVIDIA_ENDPOINT:-https://integrate.api.nvidia.com/v1/chat/completions}"

# Reasoning effort. DeepSeek V4 Pro accepts none|high|max and defaults to none
# server-side. Sent only when explicitly set, so pointing NVIDIA_MODEL at a model
# that does not accept the field cannot turn every call into a 400.
REASONING_EFFORT="${NVIDIA_REASONING_EFFORT:-}"

# Token limit (override via COUNCIL_MAX_TOKENS env var).
BASE_TOKENS="${COUNCIL_MAX_TOKENS:-2048}"
# NIM documents max_tokens for deepseek-v4-pro-0813 as 1..16384 and rejects
# anything above it, while bump_for_reasoning has a 32768 floor. --ceiling bounds
# the bump instead of skipping it, so reasoning models keep the headroom up to
# the API's real limit.
bump_for_reasoning --ceiling "${NVIDIA_TOKEN_CEILING:-16384}" \
    TOKENS "$MODEL" "$BASE_TOKENS" 'deepseek*' 'kimi-k*' '*nemotron*' 'qwen*' '*gpt-oss*'

# System instruction
SYSTEM="${VERBOSITY_PREFIX:+$VERBOSITY_PREFIX }$BASE_SYSTEM_PROMPT"

# One trap for every temp file this script owns, installed before the first of
# them exists and naming them all: a failure between here and the request would
# otherwise leave a file behind, and an EXIT trap that expands a name not yet
# assigned ends where it stands under set -u without removing anything.
CURL_CFG="" PAYLOAD_FILE="" OWNED_PROMPT_FILE=""
trap 'rm -f "$CURL_CFG" "$PAYLOAD_FILE" "$OWNED_PROMPT_FILE"' EXIT

stage_prompt_file

# temperature 1.0 / top_p 0.95 are NVIDIA's documented settings for this model
# and the ones its published benchmarks were run at — deliberately not the 0.7
# the other providers use.
# The prompt reaches jq with --rawfile, never --arg: --arg would put a --file
# sized prompt back on jq's own argv, which is what the temp file exists to avoid.
PAYLOAD=$(jq -n \
    --arg model "$MODEL" \
    --argjson tokens "$TOKENS" \
    --arg system "$SYSTEM" \
    --rawfile prompt "$PROMPT_FILE" \
    --arg effort "$REASONING_EFFORT" \
    '{
        model: $model,
        messages: [{
            role: "system",
            content: $system
        }, {
            role: "user",
            content: $prompt
        }],
        temperature: 1,
        top_p: 0.95,
        max_tokens: $tokens
    }
    + (if $effort == "" then {} else { reasoning_effort: $effort } end)')

if [[ -n "$DEBUG" ]]; then
    echo "=== DEBUG: NVIDIA NIM ===" >&2
    echo "Model: $MODEL" >&2
    echo "Endpoint: $ENDPOINT" >&2
    echo "Max tokens: $TOKENS" >&2
    echo "Reasoning effort: ${REASONING_EFFORT:-<server default>}" >&2
    echo "Timeout: ${COUNCIL_TIMEOUT}s" >&2
fi

# Keep the API key and request body off the process argv (ps-visible / OS
# argument-size limits): the key travels via a mode-600 curl config file and
# the payload via a temp file.
CURL_CFG=$(curl_secret_config "Authorization: Bearer ${API_KEY}")
PAYLOAD_FILE=$(mktemp)
printf '%s' "$PAYLOAD" > "$PAYLOAD_FILE"

# Make API call. This endpoint is a shared free tier: a request can sit in a
# queue for minutes before the first byte, then deliver the whole answer at once.
# curl_with_retry deliberately does not retry a timeout (curl exit 28) — a repeat
# request joins the back of the same queue and only makes the wait longer.
RESPONSE=$(curl_with_retry -s -X POST "$ENDPOINT" \
    --config "$CURL_CFG" \
    -H "Content-Type: application/json" \
    --data-binary @"$PAYLOAD_FILE")

if [[ -n "$DEBUG" ]]; then
    echo "=== DEBUG: Response metadata ===" >&2
    echo "$RESPONSE" | jq '{ model: .model, usage: .usage }' >&2 2>/dev/null || true
fi

# Extract text from response (OpenAI-compatible format)
TEXT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty')

# Whitespace-stripped, not just empty: a model that answers with a single space
# passes a bare -z test, and the council would store that as a successful answer
# and weigh it in the synthesis like any other.
if [[ -z "${TEXT//[[:space:]]/}" ]]; then
    ERROR=$(echo "$RESPONSE" | jq -r '(if (.error | type) == "object" then (.error.message // "") elif (.error | type) == "string" then .error else "" end) | select(. != "") // "Unknown error"')
    echo "Error from NVIDIA NIM: $ERROR" >&2
    is_model_unavailable_error "$RESPONSE" && exit 3
    exit 1
fi

echo "$TEXT"
