<p align="center">
  <strong style="font-size: 1.5em;">Commit Type Stats</strong><br>
  <em>Created to simplify understanding the composition and contribution patterns in Git projects by commit types.</em>
</p>

`commit-type-stats.sh` is a Bash script that analyzes a Git repository's commit history and provides categorized statistics by commit types such as Feat, Fix, Docs, etc. It supports listing individual commits under each type, showing top contributors, and works with both local repositories and remote Git URLs with caching for efficiency.

## Features

- Categorize commits by common types (Feat, Fix, Docs, Chore, Perf, etc.)
- Support custom prefixes and suffixes for commit message parsing
- List all commits under each category optionally
- Display top contributors per commit type optionally
- Supports analyzing remote repositories with cache for faster repeated runs
- Multilingual support for English and Chinese output
- Clear cache functionality for fresh cloning

## Usage

```bash
./commit-type-stats.sh [options]
````

### Options

* `-l`
  List all commits under each commit type.

* `-c`
  Show main contributors per commit type.

* `-prefix <str>`
  Set commit type prefix (use `|` to separate multiple). Disabled by default.

* `-suffix <str>`
  Set commit type suffix (use `|` to separate multiple). Default: `:|]|)`.

* `--no-prefix`
  Ignore prefix when matching.

* `--no-suffix`
  Ignore suffix when matching.

* `-project-name <name>`
  Manually set the project name (overrides auto-detection).

* `-project-root <path_or_git[#ref]>`
  Manually set project root path or remote git URL. Use `#branch_or_tag` to specify branch or tag.

* `--no-cache`
  Skip cache and clone remote repo temporarily.

* `--clear`
  Clear cached repositories and exit.

* `-h`, `--help`
  Show this help message.

## Bash Completion

To enable Bash completion for this script, please add the following line to your `~/.bashrc` or `~/.bash_profile`:

```bash
source path/to/your/commit-type-stats-completion.sh
```

## Examples

Analyze local repo with detailed commit listing:

```bash
./commit-type-stats.sh -l
```

Analyze remote repo, show top contributors per commit type:

```bash
./commit-type-stats.sh -project-root https://github.com/user/repo.git -c
```

Clear cached repos:

```bash
./commit-type-stats.sh --clear
```

## Requirements

* Bash shell
* Git installed and available in PATH

## License

MIT License
