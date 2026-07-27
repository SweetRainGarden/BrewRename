#!/usr/bin/env bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0

# Base directory for tests
BASE_TEST_DIR="test_env"

# Setup function to create a fresh test environment
setup() {
    rm -rf "$BASE_TEST_DIR"
    mkdir -p "$BASE_TEST_DIR"
}

# Teardown function to clean up after tests
teardown() {
    rm -rf "$BASE_TEST_DIR"
}

# Function to run a test case
run_test() {
    local test_name="$1"
    local test_func="$2"

    echo "Running test: $test_name"
    setup
    if "$test_func"; then
        echo -e "${GREEN}✔ Test passed${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✖ Test failed${NC}"
        ((TESTS_FAILED++))
    fi
    teardown
    echo "----------------------------------------"
}

# Test 1: Basic rename
test_basic_rename() {
    mkdir -p "$BASE_TEST_DIR/foo_dir"
    touch "$BASE_TEST_DIR/foo_file.txt"
    echo "foo content" > "$BASE_TEST_DIR/foo_dir/foo_file.txt"

    # Run raname.sh
    bash bin/raname.sh 'foo:bar' "$BASE_TEST_DIR" > /dev/null 2>&1

    # Verify
    [ -d "$BASE_TEST_DIR/bar_dir" ] &&
    [ -f "$BASE_TEST_DIR/bar_file.txt" ] &&
    [ -f "$BASE_TEST_DIR/bar_dir/bar_file.txt" ] &&
    grep -q "bar content" "$BASE_TEST_DIR/bar_dir/bar_file.txt"
}

# Test 2: Dry run
test_dry_run() {
    mkdir -p "$BASE_TEST_DIR/foo_dir"
    touch "$BASE_TEST_DIR/foo_file.txt"

    # Run raname.sh with --dry-run
    bash bin/raname.sh --dry-run 'foo:bar' "$BASE_TEST_DIR" > /dev/null 2>&1

    # Verify that files are unchanged
    [ -d "$BASE_TEST_DIR/foo_dir" ] &&
    [ -f "$BASE_TEST_DIR/foo_file.txt" ] &&
    [ ! -d "$BASE_TEST_DIR/bar_dir" ] &&
    [ ! -f "$BASE_TEST_DIR/bar_file.txt" ]
}

# Test 3: Copy mode with root change
test_copy_mode_root_change() {
    mkdir -p "$BASE_TEST_DIR/foo_project/src"
    touch "$BASE_TEST_DIR/foo_project/src/foo_file.txt"

    # Run raname.sh with --copy
    bash bin/raname.sh --copy 'foo:bar' "$BASE_TEST_DIR/foo_project" > /dev/null 2>&1

    # Verify original directory is untouched and the renamed copy exists
    [ -d "$BASE_TEST_DIR/foo_project" ] &&
    [ -f "$BASE_TEST_DIR/foo_project/src/foo_file.txt" ] &&
    [ -d "$BASE_TEST_DIR/bar_project" ] &&
    [ -f "$BASE_TEST_DIR/bar_project/src/bar_file.txt" ]
}

# Test 4: Exclude directories
test_exclude_directories() {
    mkdir -p "$BASE_TEST_DIR/include_dir" "$BASE_TEST_DIR/exclude_dir"
    touch "$BASE_TEST_DIR/include_dir/foo.txt"
    touch "$BASE_TEST_DIR/exclude_dir/foo.txt"

    # Run raname.sh with exclude option
    bash bin/raname.sh -e exclude_dir 'foo:bar' "$BASE_TEST_DIR" > /dev/null 2>&1

    # Verify included directory is renamed and excluded directory is unchanged
    [ -d "$BASE_TEST_DIR/include_dir" ] &&
    [ -f "$BASE_TEST_DIR/include_dir/bar.txt" ] &&
    [ -d "$BASE_TEST_DIR/exclude_dir" ] &&
    [ -f "$BASE_TEST_DIR/exclude_dir/foo.txt" ] &&
    [ ! -f "$BASE_TEST_DIR/exclude_dir/bar.txt" ]
}

# Test 5: Strict mode (case-sensitive)
test_strict_mode() {
    mkdir -p "$BASE_TEST_DIR"
    touch "$BASE_TEST_DIR/Foo.txt" "$BASE_TEST_DIR/foo.txt"

    # Run raname.sh in strict mode
    bash bin/raname.sh --strict 'foo:bar' "$BASE_TEST_DIR" > /dev/null 2>&1

    # Verify only the exact case is renamed
    [ -f "$BASE_TEST_DIR/Foo.txt" ] &&
    [ -f "$BASE_TEST_DIR/bar.txt" ] &&
    [ ! -f "$BASE_TEST_DIR/foo.txt" ]
}

# Test 6: Handle special characters
test_special_characters() {
    mkdir -p "$BASE_TEST_DIR"
    touch "$BASE_TEST_DIR/foo*file?.txt"

    # Run raname.sh
    bash bin/raname.sh --strict 'foo*file?:bar_file' "$BASE_TEST_DIR" > /dev/null 2>&1

    # Verify file is renamed correctly
    [ -f "$BASE_TEST_DIR/bar_file.txt" ] &&
    [ ! -f "$BASE_TEST_DIR/foo*file?.txt" ]
}

# Test 7: Multiple pairs
test_multiple_pairs() {
    mkdir -p "$BASE_TEST_DIR/foo_dir"
    touch "$BASE_TEST_DIR/foo_dir/baz_file.txt"

    # Run raname.sh with multiple pairs
    bash bin/raname.sh 'foo:bar,baz:qux' "$BASE_TEST_DIR" > /dev/null 2>&1

    # Verify renames
    [ -d "$BASE_TEST_DIR/bar_dir" ] &&
    [ -f "$BASE_TEST_DIR/bar_dir/qux_file.txt" ]
}

# Test 8: Copy mode without root change is rejected and leaves everything intact
test_copy_mode_no_root_change() {
    mkdir -p "$BASE_TEST_DIR/project/src"
    touch "$BASE_TEST_DIR/project/src/foo.txt"

    # Run raname.sh with --copy but no root change: must fail
    if bash bin/raname.sh --copy 'src:source' "$BASE_TEST_DIR/project" > /dev/null 2>&1; then
        return 1
    fi

    # Verify nothing was modified
    [ -d "$BASE_TEST_DIR/project/src" ] &&
    [ -f "$BASE_TEST_DIR/project/src/foo.txt" ] &&
    [ ! -d "$BASE_TEST_DIR/project/source" ]
}

# Run all tests
run_test "Basic Rename" test_basic_rename
run_test "Dry Run Mode" test_dry_run
run_test "Copy Mode with Root Change" test_copy_mode_root_change
run_test "Exclude Directories" test_exclude_directories
run_test "Strict Mode (Case-Sensitive)" test_strict_mode
run_test "Special Characters in Filenames" test_special_characters
run_test "Multiple Replacement Pairs" test_multiple_pairs
run_test "Copy Mode without Root Change" test_copy_mode_no_root_change

# Summary
echo "Test Summary:"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"

# Exit with error code if any tests failed
if [ $TESTS_FAILED -gt 0 ]; then
    exit 1
fi
