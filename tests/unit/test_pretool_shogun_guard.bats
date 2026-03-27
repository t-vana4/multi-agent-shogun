#!/usr/bin/env bats
# test_pretool_shogun_guard.bats — PreToolUse hook unit tests
#
# Calls the REAL production script with env var overrides:
#   __PRETOOL_SCRIPT_DIR → points to test temp directory (for path normalization)
#   __PRETOOL_AGENT_ID   → mocks tmux agent detection
#
# テスト構成:
#   T-GUARD-001: 非shogun → 素通り
#   T-GUARD-002: agent_id空 → 素通り
#   T-GUARD-003: Write shogun_to_karo.yaml → 許可
#   T-GUARD-004: Write saytask/ → 許可
#   T-GUARD-005: Write 任意ファイル → ブロック
#   T-GUARD-006: Edit shogun_to_karo.yaml → 許可
#   T-GUARD-007: Edit 任意ファイル → ブロック
#   T-GUARD-008: Read dashboard.md → 許可
#   T-GUARD-009: Read queue/reports/* → 許可
#   T-GUARD-010: Read 外部プロジェクト → ブロック
#   T-GUARD-011: Bash inbox_write.sh → 許可
#   T-GUARD-012: Bash ntfy.sh → 許可
#   T-GUARD-013: Bash git → ブロック
#   T-GUARD-014: Bash python3 → ブロック
#   T-GUARD-015: MCP tool → 許可
#   T-GUARD-016: Grep config/ → 許可
#   T-GUARD-017: Grep 外部パス → ブロック
#   T-GUARD-018: Bash tmux display-message → 許可
#   T-GUARD-019: Write 他agentのinbox → ブロック
#   T-GUARD-020: Read memory/* → 許可

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/scripts/pretool_shogun_guard.sh"

setup() {
    TEST_TMP="$(mktemp -d)"
    # Use the real script dir for path normalization
    # The hook normalizes file_path by stripping SCRIPT_DIR prefix
}

teardown() {
    rm -rf "$TEST_TMP"
}

# Helper: run as shogun
run_guard_shogun() {
    local json="$1"
    __PRETOOL_SCRIPT_DIR="$SCRIPT_DIR" \
    __PRETOOL_AGENT_ID="shogun" \
    run bash "$HOOK_SCRIPT" <<< "$json"
}

# Helper: run as non-shogun
run_guard_other() {
    local json="$1"
    local agent="${2:-ashigaru1}"
    __PRETOOL_SCRIPT_DIR="$SCRIPT_DIR" \
    __PRETOOL_AGENT_ID="$agent" \
    run bash "$HOOK_SCRIPT" <<< "$json"
}

# Helper: run with empty agent
run_guard_no_agent() {
    local json="$1"
    __PRETOOL_SCRIPT_DIR="$SCRIPT_DIR" \
    __PRETOOL_AGENT_ID="" \
    run bash "$HOOK_SCRIPT" <<< "$json"
}

# ─── T-GUARD-001: Non-shogun agent passes through ───
@test "T-GUARD-001: non-shogun agent passes through" {
    run_guard_other '{"tool_name":"Write","tool_input":{"file_path":"/some/random/file.py"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-002: Empty agent_id passes through ───
@test "T-GUARD-002: empty agent_id passes through" {
    run_guard_no_agent '{"tool_name":"Write","tool_input":{"file_path":"/some/random/file.py"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-003: Shogun Write to shogun_to_karo.yaml allowed ───
@test "T-GUARD-003: shogun Write to shogun_to_karo.yaml allowed" {
    run_guard_shogun "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SCRIPT_DIR/queue/shogun_to_karo.yaml\"}}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-004: Shogun Write to saytask/ allowed ───
@test "T-GUARD-004: shogun Write to saytask/ allowed" {
    run_guard_shogun "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SCRIPT_DIR/saytask/tasks.yaml\"}}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-005: Shogun Write to arbitrary file blocked ───
@test "T-GUARD-005: shogun Write to arbitrary file blocked" {
    run_guard_shogun "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SCRIPT_DIR/src/index.js\"}}"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"decision"'
    echo "$output" | grep -q '"block"'
    echo "$output" | grep -q 'F001'
}

# ─── T-GUARD-006: Shogun Edit to shogun_to_karo.yaml allowed ───
@test "T-GUARD-006: shogun Edit to shogun_to_karo.yaml allowed" {
    run_guard_shogun "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SCRIPT_DIR/queue/shogun_to_karo.yaml\"}}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-007: Shogun Edit to arbitrary file blocked ───
@test "T-GUARD-007: shogun Edit to arbitrary file blocked" {
    run_guard_shogun "{\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$SCRIPT_DIR/README.md\"}}"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"block"'
    echo "$output" | grep -q 'F001'
}

# ─── T-GUARD-008: Shogun Read dashboard.md allowed ───
@test "T-GUARD-008: shogun Read dashboard.md allowed" {
    run_guard_shogun "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$SCRIPT_DIR/dashboard.md\"}}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-009: Shogun Read queue/reports/* allowed ───
@test "T-GUARD-009: shogun Read queue/reports/ allowed" {
    run_guard_shogun "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$SCRIPT_DIR/queue/reports/ashigaru1_report.yaml\"}}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-010: Shogun Read external project file blocked ───
@test "T-GUARD-010: shogun Read external project file blocked" {
    run_guard_shogun '{"tool_name":"Read","tool_input":{"file_path":"/some/other/project/src/app.js"}}'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"block"'
    echo "$output" | grep -q 'F001'
}

# ─── T-GUARD-011: Shogun Bash inbox_write.sh allowed ───
@test "T-GUARD-011: shogun Bash inbox_write.sh allowed" {
    run_guard_shogun '{"tool_name":"Bash","tool_input":{"command":"bash scripts/inbox_write.sh karo \"cmd_050\" cmd_new shogun"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-012: Shogun Bash ntfy.sh allowed ───
@test "T-GUARD-012: shogun Bash ntfy.sh allowed" {
    run_guard_shogun '{"tool_name":"Bash","tool_input":{"command":"bash scripts/ntfy.sh \"test message\""}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-013: Shogun Bash git command blocked ───
@test "T-GUARD-013: shogun Bash git command blocked" {
    run_guard_shogun '{"tool_name":"Bash","tool_input":{"command":"git log --oneline"}}'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"block"'
    echo "$output" | grep -q 'F001'
}

# ─── T-GUARD-014: Shogun Bash python3 command blocked ───
@test "T-GUARD-014: shogun Bash python3 command blocked" {
    run_guard_shogun '{"tool_name":"Bash","tool_input":{"command":"python3 process_data.py"}}'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"block"'
    echo "$output" | grep -q 'F001'
}

# ─── T-GUARD-015: Shogun MCP tool allowed ───
@test "T-GUARD-015: shogun MCP tool allowed" {
    run_guard_shogun '{"tool_name":"mcp__memory__read_graph","tool_input":{}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-016: Shogun Grep within config/ allowed ───
@test "T-GUARD-016: shogun Grep within config/ allowed" {
    run_guard_shogun "{\"tool_name\":\"Grep\",\"tool_input\":{\"pattern\":\"language\",\"path\":\"$SCRIPT_DIR/config/\"}}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-017: Shogun Grep on external path blocked ───
@test "T-GUARD-017: shogun Grep on external path blocked" {
    run_guard_shogun '{"tool_name":"Grep","tool_input":{"pattern":"TODO","path":"/other/repo/src/"}}'
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"block"'
    echo "$output" | grep -q 'F001'
}

# ─── T-GUARD-018: Shogun Bash tmux display-message allowed ───
@test "T-GUARD-018: shogun Bash tmux display-message allowed" {
    run_guard_shogun '{"tool_name":"Bash","tool_input":{"command":"tmux display-message -t %1 -p #{@agent_id}"}}'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# ─── T-GUARD-019: Shogun Write to other agent inbox blocked ───
@test "T-GUARD-019: shogun Write to other agent inbox blocked" {
    run_guard_shogun "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SCRIPT_DIR/queue/inbox/karo.yaml\"}}"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"block"'
    echo "$output" | grep -q 'F001'
}

# ─── T-GUARD-020: Shogun Read memory/* allowed ───
@test "T-GUARD-020: shogun Read memory/ allowed" {
    run_guard_shogun "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$SCRIPT_DIR/memory/MEMORY.md\"}}"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}
