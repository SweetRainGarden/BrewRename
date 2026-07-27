#!/usr/bin/env bash

set -e  # Exit on error

VERSION="1.2.1.0"

# Default settings
strict_mode=false  # Default is loose mode
exclude_dirs=(".git")  # Always exclude .git
dry_run=false
copy_mode=false
debug=false
log_dir="${HOME}/.raname_logs"
log_file="${log_dir}/raname.log"

# Create log directory if it doesn't exist
mkdir -p "$log_dir"

# Function to log changes with timestamp and type
log() {
    local type="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$type] $message" | tee -a "$log_file"
}

# Function to check whether a name matches an excluded directory
is_excluded_name() {
    local name="$1" ex
    for ex in "${exclude_dirs[@]}"; do
        if [ "$name" = "$ex" ]; then
            return 0
        fi
    done
    return 1
}

# Function to check whether a relative path contains an excluded directory component
is_excluded() {
    local rel_path="$1"
    local part parts
    local IFS='/'
    read -ra parts <<< "$rel_path"
    for part in "${parts[@]}"; do
        if is_excluded_name "$part"; then
            return 0
        fi
    done
    return 1
}

# Function to generate case variations (one "old:new" pair per line)
generate_case_variations() {
    local old_text="$1"
    local new_text="$2"
    local variations=()

    if $strict_mode; then
        # If strict mode, only use the original pair
        variations+=("$old_text:$new_text")
    else
        # Generate all variations in loose mode
        # Original case
        variations+=("$old_text:$new_text")

        # Title Case (first letter capitalized)
        variations+=("$(echo "$old_text" | perl -pe 's/^./uc($&)/e'):$(echo "$new_text" | perl -pe 's/^./uc($&)/e')")

        # UPPERCASE
        variations+=("$(echo "$old_text" | perl -pe '$_ = uc'):$(echo "$new_text" | perl -pe '$_ = uc')")

        # lowercase
        variations+=("$(echo "$old_text" | perl -pe '$_ = lc'):$(echo "$new_text" | perl -pe '$_ = lc')")
    fi

    # Remove duplicates while preserving order
    local unique_variations=()
    for var in "${variations[@]}"; do
        if [[ ! " ${unique_variations[@]} " =~ " ${var} " ]]; then
            unique_variations+=("$var")
        fi
    done

    printf '%s\n' "${unique_variations[@]}"
}

# Function to apply all rename variations to a single path/string (literal matching)
apply_variations() {
    local text="$1"
    local variation var_old var_new
    for variation in "${all_variations[@]}"; do
        IFS=':' read -r var_old var_new <<< "$variation"
        text="${text//"$var_old"/$var_new}"
    done
    printf '%s\n' "$text"
}

# Function to apply variations to a path component-wise: an excluded component
# and everything below it stay unchanged, but its ancestors are still renamed
apply_variations_to_path() {
    local rel_path="$1"
    local part parts out=() excluded=false
    local IFS='/'
    read -ra parts <<< "$rel_path"
    for part in "${parts[@]}"; do
        if [ "$excluded" != "true" ] && is_excluded_name "$part"; then
            excluded=true
        fi
        if [ "$excluded" = "true" ]; then
            out+=("$part")
        else
            out+=("$(apply_variations "$part")")
        fi
    done
    printf '%s\n' "${out[*]}"
}

# Function to count literal occurrences of a string in a file
count_occurrences() {
    local needle="$1"
    local file="$2"
    grep -o -F -- "$needle" "$file" 2>/dev/null | wc -l | tr -d '[:space:]'
}

# Function to generate directory structure
generate_directory_structure() {
    local target="$1"
    local output_file="$2"

    # Clear the output file
    > "$output_file"

    # Get all directories except the root directory itself
    find "$target" -mindepth 1 -type d -print0 | while IFS= read -r -d '' dir; do
        echo "$dir" >> "$output_file"
    done

    # Get all files
    find "$target" -type f ! -name ".DS_Store" -print0 | while IFS= read -r -d '' file; do
        echo "$file" >> "$output_file"
    done

    # Strip the target path from the output file
    sed "s|$target/||g" "$output_file" > "$output_file.clean"
    mv "$output_file.clean" "$output_file"
}

# Function to compare directory structures (order-independent)
compare_directory_structures() {
    local expected_file="$1"
    local actual_file="$2"
    if ! diff -w <(sort "$expected_file") <(sort "$actual_file") > /dev/null; then
        echo "Error: Directory structures do not match!"
        echo "Expected structure:"
        sort "$expected_file"
        echo "Actual structure:"
        sort "$actual_file"
        return 1
    fi
    return 0
}

# Function to process file content changes (edits files under work_dir in place)
process_file_content_changes() {
    local work_dir="$1"
    local structure_dir="$2"
    local file_path patterns pair old new count actual_count

    echo "Processing file content changes..."
    while IFS='|' read -r file_path patterns; do
        if [ -f "$work_dir/$file_path" ]; then
            echo "  Processing: $file_path"

            # Split patterns into array and process each pair
            IFS=' ' read -ra content_pairs <<< "$patterns"
            for pair in "${content_pairs[@]}"; do
                IFS=':' read -r old new count <<< "$pair"
                if [ "$count" -gt 0 ]; then
                    echo "    Replacing '$old' with '$new' ($count occurrences)"
                    # Literal replacement, portable across GNU/BSD (no sed -i quirks)
                    OLD="$old" NEW="$new" perl -pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$work_dir/$file_path"

                    # Verify the change
                    actual_count=$(count_occurrences "$new" "$work_dir/$file_path")
                    if [ "$actual_count" -gt 0 ]; then
                        echo "    ✓ Verified $actual_count occurrences of '$new' in $file_path"
                    else
                        echo "    ⚠ Warning: No occurrences of '$new' found in $file_path after replacement"
                    fi
                fi
            done
        fi
    done < "$structure_dir/file_content_changes.txt"
}

# Usage guide
usage() {
  echo "Usage: raname [OPTIONS] <pairs> [directory]"
  echo ""
  echo "Options:"
  echo "  --strict              Case-sensitive matching (no case variations)"
  echo "  -e, --exclude <dirs>  Comma-separated list of directories to exclude"
  echo "  --dry-run             Show what would be changed without modifying anything"
  echo "  --copy                Create a renamed copy instead of renaming in-place"
  echo "                        (requires the root directory name to change)"
  echo "  --debug               Enable debug mode to keep temporary files"
  echo "  -v, --version         Show version"
  echo "  -h, --help            Show this help message"
  echo ""
  echo "Pairs format: old_text:new_text[,old_text2:new_text2]"
  echo "Example: raname foo:bar,dir1:dir2 ./my_project"
  exit 1
}

# Parse CLI options
while [[ $# -gt 0 ]]; do
  case "$1" in
    --strict) strict_mode=true; shift ;;
    -e|--exclude)
        [ -n "${2:-}" ] || usage
        IFS=',' read -ra extra_excludes <<< "$2"
        exclude_dirs+=("${extra_excludes[@]}")
        shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --copy) copy_mode=true; shift ;;
    --debug) debug=true; shift ;;
    -v|--version) echo "raname $VERSION"; exit 0 ;;
    -h|--help) usage ;;
    --) shift; break ;;
    -*) echo "Unknown option: $1"; usage ;;
    *) break ;;
  esac
done

# Require at least one pair
if [[ $# -lt 1 ]]; then
  usage
fi

# Parse input pairs
pairs="$1"
target_dir="${2:-.}"

if [ ! -d "$target_dir" ]; then
    echo "Error: Target directory '$target_dir' does not exist"
    exit 1
fi

# Get absolute path of target directory
target_dir=$(cd "$target_dir" && pwd)
parent_dir=$(dirname "$target_dir")
dir_name=$(basename "$target_dir")

echo "Target directory: $target_dir"
echo "Parent directory: $parent_dir"
echo "Directory name: $dir_name"

# Validate pairs before touching anything
IFS=',' read -ra PAIRS <<< "$pairs"
for pair in "${PAIRS[@]}"; do
    IFS=':' read -r old_text new_text <<< "$pair"
    if [ -z "$old_text" ] || [ -z "$new_text" ]; then
        echo "Error: Invalid pair '$pair' (expected old:new)"
        usage
    fi
done

# Create temporary directories for operations
temp_dir="$(mktemp -d)"
temp_target="$temp_dir/$dir_name"

# Create separate temporary directory for structure files
structure_dir="$(mktemp -d)"

# Copy target directory to temporary location
cp -r "$target_dir" "$temp_dir/"

# Generate original file structure list
# First get all directories
find "$temp_target" -type d -print0 | while IFS= read -r -d '' dir; do
    echo "$dir" >> "$structure_dir/original_structure.txt"
done
# Then get all files
find "$temp_target" -type f ! -name ".DS_Store" -print0 | while IFS= read -r -d '' file; do
    echo "$file" >> "$structure_dir/original_structure.txt"
done

echo "Processing in directory: $target_dir"
echo "----------------------------------------"

# Preprocess all variations
declare -a all_variations
for pair in "${PAIRS[@]}"; do
    IFS=':' read -r old_text new_text <<< "$pair"
    while IFS= read -r variation; do
        all_variations+=("$variation")
    done < <(generate_case_variations "$old_text" "$new_text")
done

# Save all variations to a file
printf '%s\n' "${all_variations[@]}" > "$structure_dir/all_variations.txt"
echo "Replacement variations:"
cat "$structure_dir/all_variations.txt"
echo "----------------------------------------"

# Check file contents for matches
echo "Checking file contents for matches..."
> "$structure_dir/file_content_changes.txt"  # Create empty file

# Read original structure and check each file
while IFS= read -r file_path; do
    if [ -f "$file_path" ]; then
        # Convert path to be relative to target directory
        rel_path="${file_path#$temp_dir/}"

        # Skip files inside excluded directories
        if is_excluded "$rel_path"; then
            continue
        fi

        matched_pairs=()
        for variation in "${all_variations[@]}"; do
            IFS=':' read -r var_old var_new <<< "$variation"
            match_count=$(count_occurrences "$var_old" "$file_path")
            if [ "$match_count" -gt 0 ]; then
                matched_pairs+=("$var_old:$var_new:$match_count")
            fi
        done

        # If any matches were found, save file path and matches in a single line
        if [ ${#matched_pairs[@]} -gt 0 ]; then
            echo "$rel_path|${matched_pairs[*]}" >> "$structure_dir/file_content_changes.txt"
        fi
    fi
done < "$structure_dir/original_structure.txt"

# Build the final structure by applying variations to each path (skipping excluded paths)
> "$structure_dir/final_structure.txt"
while IFS= read -r old_path; do
    rel_path="${old_path#$temp_dir/}"
    new_rel=$(apply_variations_to_path "$rel_path")
    echo "$temp_dir/$new_rel" >> "$structure_dir/final_structure.txt"
done < "$structure_dir/original_structure.txt"

# Get line counts
orig_count=$(wc -l < "$structure_dir/original_structure.txt")
final_count=$(wc -l < "$structure_dir/final_structure.txt")

if [ "$orig_count" != "$final_count" ]; then
    echo "Error: Line count mismatch between original and final structure files"
    echo "Original: $orig_count, Final: $final_count"
    exit 1
fi

# Strip the temp_dir path from the final structure
sed "s|$temp_dir/||g" "$structure_dir/final_structure.txt" > "$structure_dir/final_structure_clean.txt"

# Create a combined file with original and final paths
paste "$structure_dir/original_structure.txt" "$structure_dir/final_structure.txt" > "$structure_dir/combined.txt"

root_changed=false
first_line=$(head -n 1 "$structure_dir/combined.txt")

echo "----------------------------------------"
echo "raname will perform the following operations:"

new_root="$dir_name"
if [ -n "$first_line" ]; then
    old_root=$(basename "$(cut -f1 <<< "$first_line")")
    new_root=$(basename "$(cut -f2 <<< "$first_line")")
    if [ "$old_root" != "$new_root" ]; then
        root_changed=true
        echo "Root directory will be renamed from '$old_root' to '$new_root'"
    else
        echo "Root directory name '$old_root' remains unchanged"
    fi
fi
echo "File and directory changes:"

# Compare original and final structures for all paths
while IFS=$'\t' read -r old_path new_path; do
    if [ -n "$old_path" ] && [ -n "$new_path" ]; then
        # Convert paths to be relative to target directory
        rel_old_path="${old_path#$temp_dir/}"
        rel_new_path="${new_path#$temp_dir/}"
        # Only show if paths are different
        if [ "$rel_old_path" != "$rel_new_path" ]; then
            echo "     - $rel_old_path -> $rel_new_path"
        fi
    fi
done < "$structure_dir/combined.txt"

echo "----------------------------------------"

# Show file content changes
if [ -s "$structure_dir/file_content_changes.txt" ]; then
    echo "File Content Changes:"
    while IFS='|' read -r file_path patterns; do
        echo "     - $file_path"
        echo "       Replace:"
        # Split patterns into array and show each pair
        IFS=' ' read -ra content_pairs <<< "$patterns"
        for pair in "${content_pairs[@]}"; do
            IFS=':' read -r old new count <<< "$pair"
            echo "         $old -> $new ($count occurrences)"
        done
    done < "$structure_dir/file_content_changes.txt"
    echo "----------------------------------------"
fi

# If not dry run, perform actual changes
if [ "$dry_run" = "true" ]; then
    log "INFO" "Dry run completed for '$target_dir' (pairs: $pairs)."
else
    echo "Performing actual changes..."

    # Refuse copy mode when the root name does not change: the copy would
    # collide with the original directory.
    if [ "$copy_mode" = "true" ] && [ "$root_changed" != "true" ]; then
        echo "Error: --copy requires the root directory name to change"
        echo "(no rename pair matched '$dir_name'); nothing was modified."
        exit 1
    fi

    # Create final directory
    final_dir="$(mktemp -d)"

    # Apply content replacements to the temporary copy
    process_file_content_changes "$temp_dir" "$structure_dir"

    # Rebuild the tree at its renamed paths
    echo "Processing file moves and renames..."
    while IFS=$'\t' read -r old_path new_path; do
        if [ -n "$old_path" ] && [ -n "$new_path" ]; then
            rel_old_path="${old_path#$temp_dir/}"
            rel_new_path="${new_path#$temp_dir/}"

            if [ -d "$temp_dir/$rel_old_path" ]; then
                mkdir -p "$final_dir/$rel_new_path"
            elif [ -f "$temp_dir/$rel_old_path" ]; then
                if [ "$rel_old_path" != "$rel_new_path" ]; then
                    echo "  Renaming: $rel_old_path -> $rel_new_path"
                fi
                mkdir -p "$final_dir/$(dirname "$rel_new_path")"
                cp "$temp_dir/$rel_old_path" "$final_dir/$rel_new_path"
            fi
        fi
    done < "$structure_dir/combined.txt"

    # Validate final directory structure matches expected structure
    echo "Validating final directory structure..."
    actual_structure_file="$structure_dir/actual_final_structure.txt"
    generate_directory_structure "$final_dir" "$actual_structure_file"

    if ! compare_directory_structures "$structure_dir/final_structure_clean.txt" "$actual_structure_file"; then
        exit 1
    fi
    echo "Directory structure validation passed."

    if [ "$copy_mode" = "true" ]; then
        echo "Copy mode: Copying renamed directory next to the original..."

        if [ ! -w "$parent_dir" ]; then
            echo "Error: No write permission for parent directory '$parent_dir'"
            exit 1
        fi

        if [ -e "$parent_dir/$new_root" ]; then
            echo "Error: '$new_root' already exists in parent directory '$parent_dir'"
            echo "Please remove or rename the existing directory first"
            exit 1
        fi

        cp -r "$final_dir/$new_root" "$parent_dir/"
        echo "Successfully copied to: $parent_dir/$new_root"
    else
        # In-place mode: stage the result, then swap it with the original so a
        # failure at any point never destroys the original directory.
        dest_name="$dir_name"
        if [ "$root_changed" = "true" ]; then
            dest_name="$new_root"
            if [ -e "$parent_dir/$dest_name" ]; then
                echo "Error: '$dest_name' already exists in parent directory '$parent_dir'"
                echo "Please remove or rename the existing directory first"
                exit 1
            fi
        fi

        staged_dir="$parent_dir/.$dir_name.raname_new.$$"
        backup_dir="$parent_dir/.$dir_name.raname_backup.$$"

        cp -r "$final_dir/$new_root" "$staged_dir"
        mv "$target_dir" "$backup_dir"
        mv "$staged_dir" "$parent_dir/$dest_name"
        rm -rf "$backup_dir"
        echo "Renamed in place: $parent_dir/$dest_name"
    fi

    rm -rf "$final_dir"
    log "INFO" "Rename completed for '$target_dir' (pairs: $pairs)."
    echo "Changes completed successfully."
fi

# Cleanup
if [ "$debug" != "true" ]; then
    rm -rf "$temp_dir"
    rm -rf "$structure_dir"
else
    echo "Debug mode: Structure directory is at: $structure_dir"
    echo "Debug mode: Temporary directory is at: $temp_dir"
fi
