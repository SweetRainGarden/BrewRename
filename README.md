# raname

A command-line utility to rename files and directories recursively, replacing text in both file/directory names and their contents.

## Features

- Raname files and directories recursively
- Replace text in file contents
- Case variations handled automatically (original, Title, UPPER, lower) unless `--strict`
- Copy mode to create ranamed copies instead of renaming in-place
- Dry run mode to preview changes
- Exclude specific directories (`.git` is always excluded)
- The original directory is never deleted until the renamed result is fully staged

## Installation

### Using Homebrew

```bash
# Add the tap
brew tap SweetRainGarden/raname

# Install the formula
brew install raname
```

> Note: installing from the tap requires a published release tag. Until one
> exists, use the manual installation below.

### Manual Installation

```bash
# Clone the repository
git clone https://github.com/SweetRainGarden/homebrew-raname.git
cd homebrew-raname

# Make the script executable
chmod +x bin/raname.sh

# Optional: Add to your PATH
ln -s "$(pwd)/bin/raname.sh" /usr/local/bin/raname
```

## Usage

```bash
raname [options] <pairs> [directory]
```

Replacement pairs use the format `old:new`, with multiple pairs separated by commas: `old1:new1,old2:new2`. The directory defaults to the current directory.

### Options

- `--strict`: Case-sensitive matching (no automatic case variations)
- `-e, --exclude <dirs>`: Comma-separated list of directories to exclude (`.git` is always excluded)
- `--dry-run`: Show what would be ranamed without making changes
- `--copy`: Create a ranamed copy next to the original instead of renaming in-place (requires the root directory name to change)
- `--debug`: Keep temporary working directories for inspection
- `-v, --version`: Show version
- `-h, --help`: Show help message

### Examples

```bash
# Basic raname (also matches Foo/FOO/foo by default)
raname foo:bar ./my_project

# Strict, case-sensitive raname
raname --strict foo:bar ./my_project

# Multiple replacement pairs
raname foo:bar,baz:qux ./my_project

# Dry run to preview changes
raname --dry-run foo:bar ./my_project

# Create a ranamed copy instead of renaming in-place
raname --copy foo:bar ./my_project

# Exclude directories
raname -e node_modules,vendor foo:bar ./my_project
```

## How it Works

1. The target directory is copied to a temporary location.
2. Content replacements and path renames are computed and shown (this is all `--dry-run` does).
3. The renamed tree is built in a staging area and its structure is validated.
4. In-place mode: the staged result is swapped with the original atomically — the original is only removed after the renamed tree is fully in place. Copy mode: the staged result is copied next to the original, which is left untouched.

Excluded directories (always including `.git`) are carried over unchanged: their names and contents are never modified, though they move along with renamed parent directories.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
