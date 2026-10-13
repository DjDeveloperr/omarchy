#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/bin"
cat >"$tmpdir/bin/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s\n' "shell $*" >>"$CALL_LOG"
printf '%s\n' "$IPC_REPLY"
exit "$IPC_EXIT"
SH
cat >"$tmpdir/bin/omarchy-system-wake" <<'SH'
#!/bin/bash
echo wake >>"$CALL_LOG"
SH
chmod +x "$tmpdir/bin/"*

export CALL_LOG="$tmpdir/calls"
export PATH="$tmpdir/bin:$PATH"
export IPC_REPLY="ok" IPC_EXIT=0
"$ROOT/bin/omarchy-system-lid-open"
[[ $(<"$CALL_LOG") == "shell lock wake" ]] || fail "lid-open uses the lock's power queue"
pass "lid-open uses the lock's power queue without a competing wake command"

: >"$CALL_LOG"
export IPC_REPLY="Function not found." IPC_EXIT=1
"$ROOT/bin/omarchy-system-lid-open"
mapfile -t calls <"$CALL_LOG"
[[ ${calls[0]} == "shell lock wake" && ${calls[1]} == "wake" ]] || fail "lid-open falls back when the shell cannot wake"
pass "lid-open wakes through the normal helper when lock IPC is unavailable"

run_node_test <<'JS'
const fs = require('fs')
const bindings = fs.readFileSync(path.join(root, 'default/hypr/bindings/utilities.lua'), 'utf8')
for (const name of ['Lid Switch', 'Apple SMC power/lid events']) {
  assert(bindings.includes('o.bind("switch:off:' + name + '", nil, "omarchy-system-lid-open", { locked = true })'), name + ' wakes even while locked')
}
JS
