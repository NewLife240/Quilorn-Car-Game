#!/usr/bin/env bash
# Runs every headless test and exits non-zero if any of them fails.
#   tests/run_tests.sh              # all tests
#   tests/run_tests.sh hill         # only tests whose name contains "hill"
# Env: GODOT=path/to/godot (default: godot), JOBS=parallel runs (default: CPU count),
#      LOG_DIR=where the per-test logs go (default: a temp dir).
# A test fails if it exits non-zero, prints a SCRIPT ERROR, or never prints its RESULT line.
set -u
cd "$(dirname "$0")/.."
GODOT=${GODOT:-godot}
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}
LOG_DIR=${LOG_DIR:-$(mktemp -d)}
FILTER=${1:-}
mkdir -p "$LOG_DIR"

DRIVE="res://tests/drive_test.tscn -- real notraffic vmax=90 stop_s=7 max_temp=105"
# name | scene and arguments
# Thresholds sit about 10-15% under what the cars did on 2026-11-27, after the gearbox and
# worn-parts fixes: a gearbox that stops upshifting or a car that loses power on worn parts fails.
TESTS=(
	"assembly|res://tests/assembly_test.tscn"
	"interact|res://tests/interact_test.tscn"
	"exit|res://tests/exit_test.tscn"
	"kombi_road_worn48|$DRIVE vid=kombi where=road cond=48 dur=30 min_gear=3 min_kmh=70 min_pwr=0.6"
	"kombi_road_worn70|$DRIVE vid=kombi where=road cond=70 dur=30 min_gear=3 min_kmh=75 min_pwr=0.75"
	"kombi_road_new|$DRIVE vid=kombi where=road cond=100 dur=30 min_gear=4 min_kmh=80 min_pwr=0.95"
	"kombi_hill_worn48|$DRIVE vid=kombi where=hill cond=48 dur=40 min_gear=2 min_climb_kmh=38 min_pwr=0.6"
	"kombi_hill_worn70|$DRIVE vid=kombi where=hill cond=70 dur=40 min_gear=3 min_climb_kmh=48 min_pwr=0.75"
	"kombi_hill_new|$DRIVE vid=kombi where=hill cond=100 dur=40 min_gear=3 min_climb_kmh=52 min_pwr=0.95"
	"hatch_road_worn48|$DRIVE vid=hatch where=road cond=48 dur=30 min_gear=3 min_kmh=70 min_pwr=0.6"
	"stepvan_hill_new|$DRIVE vid=stepvan where=hill cond=100 dur=40 min_gear=3 min_climb_kmh=40 min_pwr=0.95"
)

echo "Importing project..."
"$GODOT" --headless --path . --import >"$LOG_DIR/import.log" 2>&1 || { echo "import failed, see $LOG_DIR/import.log"; exit 1; }

run_one() {
	local name=$1 cmd=$2 log="$LOG_DIR/$1.log"
	# shellcheck disable=SC2086
	timeout 600 "$GODOT" --headless --path . $cmd >"$log" 2>&1
	local rc=$?
	if [ $rc -eq 0 ] && grep -q "SCRIPT ERROR" "$log"; then rc=3; fi
	if [ $rc -eq 0 ] && ! grep -q "^RESULT .* PASSED" "$log"; then rc=4; fi
	echo "$rc" >"$log.rc"
}

pids=()
names=()
for entry in "${TESTS[@]}"; do
	name=${entry%%|*}
	cmd=${entry#*|}
	[ -n "$FILTER" ] && [[ "$name" != *"$FILTER"* ]] && continue
	while [ "$(jobs -rp | wc -l)" -ge "$JOBS" ]; do sleep 1; done
	echo "RUN   $name"
	run_one "$name" "$cmd" &
	names+=("$name")
done
wait

fails=0
echo
for name in "${names[@]}"; do
	rc=$(cat "$LOG_DIR/$name.log.rc" 2>/dev/null || echo 99)
	if [ "$rc" = "0" ]; then
		echo "PASS  $name"
	else
		fails=$((fails + 1))
		case $rc in
			2) why="timed out";; 3) why="script error";; 4) why="no RESULT line";; 124) why="killed after 600 s";; *) why="exit $rc";;
		esac
		echo "FAIL  $name ($why) - $LOG_DIR/$name.log"
		grep -E "  FAIL |SCRIPT ERROR" "$LOG_DIR/$name.log" | head -10 | sed 's/^/      /'
	fi
done
echo
echo "${#names[@]} tests, $fails failed. Logs: $LOG_DIR"
[ "$fails" -eq 0 ]
