#!/usr/bin/env bats
# ABOUTME: Tests for scripts/lib/tokens.sh
# ABOUTME: Validates the reasoning-model token bump helper

load test_helper

LIB="${LIB_DIR}/tokens.sh"

setup() {
    unset BUMPED
}

@test "tokens: bump_for_reasoning bumps to 32768 for gemini-3*" {
    source "$LIB"
    bump_for_reasoning BUMPED "gemini-3.1-pro-preview" 2048 'gemini-3*' '*thinking*'
    [ "$BUMPED" = "32768" ]
}

@test "tokens: bump_for_reasoning leaves base for non-matching models" {
    source "$LIB"
    bump_for_reasoning BUMPED "gemini-1.5-pro" 2048 'gemini-3*' '*thinking*'
    [ "$BUMPED" = "2048" ]
}

@test "tokens: bump_for_reasoning matches *reasoning* glob" {
    source "$LIB"
    bump_for_reasoning BUMPED "grok-4.20-reasoning" 2048 '*reasoning*'
    [ "$BUMPED" = "32768" ]
}

@test "tokens: bump_for_reasoning matches grok-build-* glob" {
    source "$LIB"
    bump_for_reasoning BUMPED "grok-build-0.1" 2048 'grok-build-*'
    [ "$BUMPED" = "32768" ]
}

@test "tokens: bump_for_reasoning matches sonar-reasoning prefix" {
    source "$LIB"
    bump_for_reasoning BUMPED "sonar-reasoning-pro" 2048 'sonar-reasoning*'
    [ "$BUMPED" = "32768" ]
}

@test "tokens: bump_for_reasoning leaves sonar (non-reasoning) alone" {
    source "$LIB"
    bump_for_reasoning BUMPED "sonar" 2048 'sonar-reasoning*'
    [ "$BUMPED" = "2048" ]
}

@test "tokens: bump_for_reasoning uses 8x base when 8x exceeds 32768" {
    source "$LIB"
    bump_for_reasoning BUMPED "gemini-3.1-pro" 8192 'gemini-3*'
    # 8192 * 8 = 65536, exceeds floor of 32768
    [ "$BUMPED" = "65536" ]
}

@test "tokens: bump_for_reasoning floors to 32768 when 8x base is below" {
    source "$LIB"
    bump_for_reasoning BUMPED "gemini-3.1-pro" 1024 'gemini-3*'
    # 1024 * 8 = 8192, below floor → bumps to 32768
    [ "$BUMPED" = "32768" ]
}

@test "tokens: bump_for_reasoning accepts multiple patterns" {
    source "$LIB"
    bump_for_reasoning BUMPED "anthropic-thinking-v1" 2048 'gemini-3*' '*thinking*' 'o3-*'
    [ "$BUMPED" = "32768" ]
}

# --- --ceiling -------------------------------------------------------------
# Some APIs cap max_tokens below the 32768 floor: NIM documents 1..16384 for
# deepseek-v4-pro-0813 and 400s anything higher.

@test "tokens: bump_for_reasoning without --ceiling still bumps a matching model" {
    source "$LIB"
    # The optional prefix must not shift the positional arguments.
    bump_for_reasoning BUMPED "deepseek-v4-pro-0813" 4096 'deepseek*'
    [ "$BUMPED" = "32768" ]
}

@test "tokens: bump_for_reasoning without --ceiling still leaves a non-match alone" {
    source "$LIB"
    bump_for_reasoning BUMPED "deepseek-v4-pro-0813" 4096 'gemini-3*'
    [ "$BUMPED" = "4096" ]
}

@test "tokens: --ceiling below the 32768 floor wins over the floor" {
    source "$LIB"
    # 2048 * 8 = 16384, raised to the 32768 floor, then clamped back to the
    # limit the API actually accepts. A clamp applied before the floor would be
    # undone by it.
    bump_for_reasoning --ceiling 16384 BUMPED "deepseek-v4-pro-0813" 2048 'deepseek*'
    [ "$BUMPED" = "16384" ]
}

@test "tokens: --ceiling above the bumped result changes nothing" {
    source "$LIB"
    bump_for_reasoning --ceiling 65536 BUMPED "gemini-3.1-pro-preview" 2048 'gemini-3*'
    [ "$BUMPED" = "32768" ]
}

@test "tokens: --ceiling clamps a non-matching model whose base is over the ceiling" {
    source "$LIB"
    # The no-match path clamps too: a caller that raised COUNCIL_MAX_TOKENS over
    # the API's limit would otherwise slip past unbounded.
    bump_for_reasoning --ceiling 16384 BUMPED "deepseek-v4-pro-0813" 32768 'gemini-3*'
    [ "$BUMPED" = "16384" ]
}

@test "tokens: --ceiling without a value names the problem instead of eating OUT_VAR" {
    run "$HOST_BASH" -c "source '$LIB'; bump_for_reasoning --ceiling"
    [ "$status" -ne 0 ]
    [[ "$output" == *"--ceiling requires a value"* ]]
}

@test "tokens: a clamp that does not fire leaves a set -e caller alive" {
    # (( ... )) && x=y returns nonzero when the condition is false. As the last
    # command of the function that status is the function's, and under set -e it
    # would take the caller down. printf -v runs after the clamp for that reason.
    run "$HOST_BASH" -c "set -e
source '$LIB'
seat() { bump_for_reasoning --ceiling 16384 OUT 'plain-model' 2048 'deepseek*'; }
seat
echo \"SURVIVED=\$OUT\""
    [ "$status" -eq 0 ]
    [[ "$output" == *"SURVIVED=2048"* ]]
}
