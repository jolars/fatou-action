#!/usr/bin/env sh
set -eu

installer="$(cd "$(dirname "$0")/.." && pwd)/scripts/install-fatou.sh"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT INT TERM
export FATOU_TEST_DIR="$test_dir"
export FATOU_INSTALL_DIR="$test_dir/install"
export FATOU_VERSION=v0.0.0
export FATOU_VERIFY_CHECKSUM=true

mkdir -p "$test_dir/bin" "$test_dir/fixture"
printf 'test binary\n' > "$test_dir/fixture/fatou"
tar -czf "$test_dir/archive.tar.gz" -C "$test_dir/fixture" fatou
if command -v sha256sum >/dev/null 2>&1; then
	sha256sum "$test_dir/archive.tar.gz" > "$test_dir/checksum"
else
	shasum -a 256 "$test_dir/archive.tar.gz" > "$test_dir/checksum"
fi

# Replace network clients so failures are deterministic and require no token.
cat > "$test_dir/bin/curl" <<'EOF'
#!/usr/bin/env sh
set -eu
while [ "$#" -gt 0 ]; do
	case "$1" in
	https://*) url="$1" ;;
	-o) shift; destination="$1" ;;
	esac
	shift
done
case "$url" in
*.sha256) kind=checksum; failures="$FATOU_TEST_CHECKSUM_FAILURES"; source=checksum ;;
*) kind=archive; failures="$FATOU_TEST_ARCHIVE_FAILURES"; source=archive.tar.gz ;;
esac
count_file="$FATOU_TEST_DIR/$kind.count"
count=0
if [ -f "$count_file" ]; then count="$(cat "$count_file")"; fi
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"
if [ "$count" -le "$failures" ]; then
	printf 'partial download\n' > "$destination"
	echo 'curl: (35) Recv failure: Connection reset by peer' >&2
	exit 35
fi
if [ "$kind" = checksum ] && [ "$FATOU_TEST_BAD_CHECKSUM" = true ]; then
	printf 'incorrect-checksum\n' > "$destination"
else
	cp "$FATOU_TEST_DIR/$source" "$destination"
fi
EOF
cat > "$test_dir/bin/gh" <<'EOF'
#!/usr/bin/env sh
if [ "$FATOU_TEST_BAD_PROVENANCE" = true ]; then
	echo 'attestation signature verification failed' >&2
	exit 1
fi
EOF
cat > "$test_dir/bin/sleep" <<'EOF'
#!/usr/bin/env sh
exit 0
EOF
chmod +x "$test_dir/bin/"*
export PATH="$test_dir/bin:$PATH"

failures=0
run_case() {
	name="$1"
	export FATOU_TEST_ARCHIVE_FAILURES="$2" FATOU_TEST_CHECKSUM_FAILURES="$3"
	export FATOU_TEST_BAD_CHECKSUM="$4" FATOU_TEST_BAD_PROVENANCE="$5"
	expected_status="$6" expected_archive_attempts="$7" expected_checksum_attempts="$8"
	expected_message="$9"
	rm -rf "$FATOU_INSTALL_DIR"
	printf '0\n' > "$test_dir/archive.count"
	printf '0\n' > "$test_dir/checksum.count"
	status=0
	sh "$installer" > "$test_dir/output" 2>&1 || status=$?
	passed=true
	if [ "$expected_status" = success ]; then
		if [ "$status" -ne 0 ] || ! cmp -s "$test_dir/fixture/fatou" "$FATOU_INSTALL_DIR/fatou"; then
			passed=false
		fi
	elif [ "$status" -eq 0 ] || [ -e "$FATOU_INSTALL_DIR/fatou" ]; then
		passed=false
	fi
	if [ "$(cat "$test_dir/archive.count")" -ne "$expected_archive_attempts" ] ||
		[ "$(cat "$test_dir/checksum.count")" -ne "$expected_checksum_attempts" ]; then
		passed=false
	fi
	if ! grep -Fq "$expected_message" "$test_dir/output"; then
		passed=false
	fi
	if [ "$passed" = true ]; then
		printf 'PASS: %s\n' "$name"
	else
		printf 'FAIL: %s (exit %s, archive attempts %s, checksum attempts %s)\n' \
			"$name" "$status" "$(cat "$test_dir/archive.count")" "$(cat "$test_dir/checksum.count")"
		cat "$test_dir/output"
		failures=$((failures + 1))
	fi
}

run_case 'successful download' 0 0 false false success 1 1 'Checksum verified.'
run_case 'interrupted archive recovers on the last attempt' 3 0 false false success 4 1 'Checksum verified.'
run_case 'archive retries are bounded' 10 0 false false failure 4 0 'Connection reset by peer'
run_case 'interrupted checksum recovers on the last attempt' 0 3 false false success 1 4 'Checksum verified.'
run_case 'unavailable checksum still warns and continues' 0 10 false false success 1 4 'skipping verification.'
run_case 'checksum mismatch aborts after a retry' 1 0 true false failure 2 1 'Checksum mismatch'
run_case 'invalid provenance aborts after a retry' 1 0 false true failure 2 1 'Provenance verification failed'

[ "$failures" -eq 0 ]
