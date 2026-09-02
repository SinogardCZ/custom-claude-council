#!/bin/bash
# ABOUTME: Token-limit helper that bumps the cap for reasoning models
# ABOUTME: Source from provider scripts and call bump_for_reasoning before API request

# Reasoning models share the maxOutputTokens cap between internal "thinking"
# and visible output. A 2048 cap can leave only a few hundred tokens for the
# actual response after the model burns most on chain-of-thought, producing
# silent mid-sentence truncation. This helper bumps the cap to 8x base
# (minimum 32768, matching OpenAI's recommendation) when the model name
# matches one of the caller-supplied glob patterns.
#
# The 32768 minimum is a floor, not merely a multiplier, and some APIs cap
# max_tokens below it: NVIDIA NIM documents 1..16384 for deepseek-v4-pro-0813
# and rejects anything higher, so an unbounded bump turns every call into a 400.
# --ceiling N bounds the result for those. The clamp is applied last, after the
# floor — applied before it, the floor would raise the value straight back over
# the API's limit. Callers that pass no --ceiling are unaffected.
#
# Usage: bump_for_reasoning [--ceiling N] OUT_VAR <model> <base_tokens> <pattern> [<pattern>...]
#
# Examples:
#   bump_for_reasoning TOKENS "$MODEL" "$BASE_TOKENS" 'gemini-3*' '*thinking*'
#   bump_for_reasoning --ceiling 16384 TOKENS "$MODEL" "$BASE_TOKENS" 'deepseek*'
bump_for_reasoning() {
    # An option prefix rather than a fifth positional: the pattern list is
    # variadic, so anything appended would be read as a pattern.
    local ceiling=0
    if [[ "${1:-}" == "--ceiling" ]]; then
        ceiling="${2:?--ceiling requires a value}"
        shift 2
    fi

    local __out="$1"
    local model="$2"
    local base="$3"
    shift 3

    local result="$base"
    local pattern
    for pattern in "$@"; do
        # shellcheck disable=SC2053
        if [[ "$model" == $pattern ]]; then
            result=$(( base * 8 ))
            (( result < 32768 )) && result=32768
            break
        fi
    done

    # Last, and on both paths: a caller that raised COUNCIL_MAX_TOKENS above the
    # ceiling would otherwise slip past on the no-match path.
    (( ceiling > 0 && result > ceiling )) && result=$ceiling

    printf -v "$__out" '%s' "$result"
}
