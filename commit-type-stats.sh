#!/bin/bash

show_list=0
show_contrib=0
prefix=''
suffix=':|]|)'
project_name=''
project_root=''
tmpdir=''
clean_tmp=0
use_cache=1
clear_cache=0

lang_code="${LANG,,}"
if [[ "$lang_code" == *"zh"* ]]; then
  L_usage_title="用法"
  L_desc="分析 git 提交历史，并按类型显示统计信息。"
  L_opt_l="-l                                列出每个类型下的所有提交记录。"
  L_opt_c="-c                                显示每个类型的主要贡献者。"
  L_opt_prefix="-prefix <str>                     设置提交类型的前缀 (可用'|'分隔多个)。默认不启用。"
  L_opt_suffix="-suffix <str>                     设置提交类型的后缀 (可用'|'分隔多个)。默认为':|]|)'。"
  L_opt_no_prefix="--no-prefix                       匹配时忽略前缀。"
  L_opt_no_suffix="--no-suffix                       匹配时忽略后缀。"
  L_opt_project_name="-project-name <name>              手动设置项目名称 (覆盖自动检测)。"
  L_opt_project_root="-project-root <path_or_git[#ref]> 手动设置项目根目录或远程仓库地址，远程可用 '#branch_or_tag' 指定分支/标签。"
  L_opt_no_cache="--no-cache                        跳过缓存，临时克隆远程仓库（不会写入缓存）。"
  L_opt_clear="--clear                           清理缓存的 repos 并退出。"
  L_opt_help="-h, --help                        显示此帮助信息。"
  L_project="项目"
  L_contrib="[主要贡献者: "
  L_contrib_list="[贡献者: "
  L_total="总计"
  L_detect_remote="检测到远程仓库:"
  L_cloning="正在克隆到:"
  L_using_cache="使用缓存目录:"
  L_fetch_failed="警告: 更新缓存失败，尝试重新克隆..."
  L_clone_failed="错误: git clone 失败"
  L_cd_failed="错误: 无法进入目录"
  L_cache_cleared="缓存已清理"
else
  L_usage_title="Usage"
  L_desc="Analyze git commit history and display statistics by type."
  L_opt_l="-l                                List all commit records under each type."
  L_opt_c="-c                                Show main contributors for each type."
  L_opt_prefix="-prefix <str>                     Set commit type prefix (use '|' to separate multiple). Disabled by default."
  L_opt_suffix="-suffix <str>                     Set commit type suffix (use '|' to separate multiple). Default: ':|]|)'."
  L_opt_no_prefix="--no-prefix                       Ignore prefix when matching."
  L_opt_no_suffix="--no-suffix                       Ignore suffix when matching."
  L_opt_project_name="-project-name <name>              Manually set the project name (overrides auto-detection)."
  L_opt_project_root="-project-root <path_or_git[#ref]> Manually set project root or remote git URL; use '#branch_or_tag' to specify branch/tag."
  L_opt_no_cache="--no-cache                        Skip cache and do a temporary clone (won't write cache)."
  L_opt_clear="--clear                           Clear cached repos and exit."
  L_opt_help="-h, --help                        Show this help message."
  L_project="Project"
  L_contrib="[Top contributors: "
  L_contrib_list="[Contributors: "
  L_total="Total"
  L_detect_remote="Detected remote repository:"
  L_cloning="Cloning to:"
  L_using_cache="Using cache dir:"
  L_fetch_failed="Warning: updating cache failed, trying fresh clone..."
  L_clone_failed="Error: git clone failed"
  L_cd_failed="Error: cannot cd to"
  L_cache_cleared="Cache cleared"
fi

usage() {
  echo "$L_usage_title: $(basename "$0") [-l] [-c] [-prefix <str>] [-suffix <str>] [--no-prefix] [--no-suffix] [-project-name <name>] [-project-root <path_or_git[#ref]>] [--no-cache] [--clear] [-h]"
  echo "$L_desc"
  echo
  echo "Options:"
  echo "  $L_opt_l"
  echo "  $L_opt_c"
  echo "  $L_opt_prefix"
  echo "  $L_opt_suffix"
  echo "  $L_opt_no_prefix"
  echo "  $L_opt_no_suffix"
  echo "  $L_opt_project_name"
  echo "  $L_opt_project_root"
  echo "  $L_opt_no_cache"
  echo "  $L_opt_clear"
  echo "  $L_opt_help"
}

is_git_url() {
  local url="$1"
  if [[ -z "$url" ]]; then return 1; fi
  if [[ "$url" =~ ^(git@|ssh://|http://|https://) ]]; then return 0; fi
  if [[ "$url" =~ ^[^/]+:[^/].+ ]]; then return 0; fi
  return 1
}

compute_hash() {
  local s="$1"
  if command -v md5sum >/dev/null 2>&1; then
    printf "%s" "$s" | md5sum | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    printf "%s" "$s" | shasum -a1 | awk '{print $1}'
  else
    printf "%s" "$s" | base64 | tr -cd '[:alnum:]' | cut -c1-32
  fi
}

trap 'if [[ $clean_tmp -eq 1 && -n "$tmpdir" && -d "$tmpdir" ]]; then rm -rf "$tmpdir"; fi' EXIT

while [[ $# -gt 0 ]]; do
  case "$1" in
    -l) show_list=1; shift ;;
    -c) show_contrib=1; shift ;;
    -prefix) prefix="$2"; shift 2 ;;
    -suffix) suffix="$2"; shift 2 ;;
    --no-prefix) prefix=""; shift ;;
    --no-suffix) suffix=""; shift ;;
    --no-cache) use_cache=0; shift ;;
    --clear) clear_cache=1; shift ;;
    -project-name)
      if [[ -n "$2" ]]; then project_name="$2"; shift 2; else echo "Error: -project-name requires a value." >&2; exit 1; fi
      ;;
    -project-root)
      if [[ -n "$2" ]]; then project_root="$2"; shift 2; else echo "Error: -project-root requires a value." >&2; exit 1; fi
      ;;
    -h|--help) usage; exit 0 ;;
    *) shift ;;
  esac
done

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/commit-type-stats/repos"

if [[ $clear_cache -eq 1 ]]; then
  if [[ -d "$cache_root" ]]; then
    rm -rf "$cache_root"
    echo -e "\e[1;32m$L_cache_cleared: $cache_root\e[0m"
    exit 0
  else
    echo -e "\e[1;33m$L_cache_cleared: $cache_root (not exists)\e[0m"
    exit 0
  fi
fi

if [[ -n "$project_root" ]]; then
  if is_git_url "$project_root"; then
    repo_url="$project_root"
    ref=""
    if [[ "$project_root" == *"#"* ]]; then
      repo_url="${project_root%%#*}"
      ref="${project_root#*#}"
    fi

    if [[ $use_cache -eq 1 ]]; then
      mkdir -p "$cache_root"
      key="$(compute_hash "${repo_url}::${ref}")"
      safe_ref="${ref//\//-}"
      cache_repo_dir="$cache_root/${key}${safe_ref:+-}${safe_ref}"
      if [[ -d "$cache_repo_dir/.git" ]]; then
        echo -e "\e[1;33m$L_using_cache $cache_repo_dir\e[0m"
        cd "$cache_repo_dir" || { echo "$L_cd_failed $cache_repo_dir" >&2; exit 1; }
        if ! git fetch --all --tags --prune --quiet 2>/dev/null; then
          echo -e "\e[1;33m$L_fetch_failed\e[0m"
          rm -rf "$cache_repo_dir"
        else
          if [[ -n "$ref" ]]; then
            git checkout --force "$ref" 2>/dev/null || git checkout --force "origin/$ref" 2>/dev/null || true
          else
            default_branch=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
            if [[ -n "$default_branch" ]]; then
              git checkout --force "$default_branch" 2>/dev/null || true
            fi
          fi
        fi
      fi

      if [[ ! -d "$cache_repo_dir/.git" ]]; then
        mkdir -p "$cache_repo_dir"
        echo -e "\e[1;33m$L_cloning $cache_repo_dir\e[0m"
        if [[ -n "$ref" ]]; then
          if ! git clone --branch "$ref" "$repo_url" "$cache_repo_dir" 2>/dev/null; then
            echo "$L_clone_failed" >&2
            rm -rf "$cache_repo_dir"
            exit 1
          fi
        else
          if ! git clone "$repo_url" "$cache_repo_dir" 2>/dev/null; then
            echo "$L_clone_failed" >&2
            rm -rf "$cache_repo_dir"
            exit 1
          fi
        fi
      fi

      cd "$cache_repo_dir" || { echo "$L_cd_failed $cache_repo_dir" >&2; exit 1; }
      project_root="$cache_repo_dir"
      clean_tmp=0
    else
      echo -e "\e[1;33m$L_detect_remote $repo_url ${ref:+(#$ref)}\e[0m"
      tmpdir=$(mktemp -d)
      echo -e "\e[1;33m$L_cloning $tmpdir\e[0m"
      if [[ -n "$ref" ]]; then
        if ! git clone --branch "$ref" "$repo_url" "$tmpdir" 2>/dev/null; then
          echo "$L_clone_failed" >&2
          rm -rf "$tmpdir"
          exit 1
        fi
      else
        if ! git clone "$repo_url" "$tmpdir" 2>/dev/null; then
          echo "$L_clone_failed" >&2
          rm -rf "$tmpdir"
          exit 1
        fi
      fi
      cd "$tmpdir" || { echo "$L_cd_failed $tmpdir" >&2; rm -rf "$tmpdir"; exit 1; }
      project_root="$tmpdir"
      clean_tmp=1
    fi
  else
    if ! cd "$project_root" 2>/dev/null; then
      echo "$L_cd_failed $project_root" >&2
      exit 1
    fi
    project_root="$(pwd)"
  fi
else
  project_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "Error: Not a git repository and no project root specified." >&2
    exit 1
  }
  cd "$project_root" || { echo "$L_cd_failed $project_root" >&2; exit 1; }
fi

if [[ -z "$project_name" ]]; then
  project_name=$(basename "$project_root")
fi

echo -e "\e[1;36m$L_project: $project_name\e[0m"

types=(Feat Chore Fix Improvement Perf Misc Docs Refactor "Update/Add" Adjust Translate 'Revert/Reapply' Merge Others)

declare -A colors=(
  [Feat]='\e[38;5;82m'
  [Chore]='\e[38;5;220m'
  [Fix]='\e[38;5;208m'
  [Improvement]='\e[38;5;39m'
  [Perf]='\e[38;5;33m'
  [Misc]='\e[38;5;141m'
  [Docs]='\e[38;5;250m'
  [Refactor]='\e[38;5;45m'
  [Update/Add]='\e[38;5;51m'
  [Adjust]='\e[38;5;99m'
  [Translate]='\e[38;5;213m'
  [Revert/Reapply]='\e[38;5;196m'
  [Merge]='\e[38;5;50m'
  [Others]='\e[38;5;244m'
)

declare -A commits_by_type
declare -A counts
declare -A contrib_counts

total=0
max_author_len=0

while IFS=$'\t' read -r author line; do
  matches=""
  content_to_parse=""
  if [[ "$line" =~ ^(Revert|Reapply) ]]; then
    matches="Revert/Reapply"
  elif [[ "$line" =~ ^Merge ]]; then
    matches="Merge"
  else
    IFS='|' read -ra prefix_list <<< "$prefix"
    IFS='|' read -ra suffix_list <<< "$suffix"
    for pre in "${prefix_list[@]:-}"; do
      for suf in "${suffix_list[@]:-}"; do
        if [[ -n "$pre" && -n "$suf" && "$line" == *"$pre"* && "$line" == *"$suf"* ]]; then
          temp=${line#*$pre}
          content_to_parse=${temp%%$suf*}
          break 2
        elif [[ -n "$pre" && -z "$suf" && "$line" == *"$pre"* ]]; then
          content_to_parse=${line#*$pre}
          break 2
        elif [[ -z "$pre" && -n "$suf" && "$line" == *"$suf"* ]]; then
          content_to_parse=${line%%$suf*}
          break 2
        elif [[ -z "$pre" && -z "$suf" ]]; then
          content_to_parse="$line"
          break 2
        fi
      done
    done
    if [[ -n "$content_to_parse" ]]; then
      IFS='|' read -ra parts <<< "$content_to_parse"
      for part in "${parts[@]}"; do
        t=$(echo "$part" | xargs -0)
        t_lower=${t,,}
        for type_keyword in Feat Chore Fix Improvement Perf Misc Docs Refactor "Update/Add" Adjust Translate; do
          if [[ "$type_keyword" == "Update/Add" ]]; then
            if [[ "$t_lower" == *"update"* || "$t_lower" == *"add"* ]]; then
              matches+="Update/Add "
            fi
          elif [[ "$type_keyword" == "Improvement" ]]; then
            if [[ "$t_lower" == *"improve"* ]]; then
              matches+="Improvement "
            fi
          else
            if [[ "$t_lower" == *"${type_keyword,,}"* ]]; then
              matches+="$type_keyword "
            fi
          fi
        done
      done
      matches=$(echo "$matches" | xargs -0)
    fi
    if [ -z "$matches" ]; then
      matches="Others"
    fi
  fi
  ((total++))
  len=${#author}
  (( len > max_author_len )) && max_author_len=$len
  for t in $matches; do
    commits_by_type["$t"]+="$author"$'\t'"$line"$'\n'
    ((counts["$t"]++))
    key="$t,$author"
    ((contrib_counts["$key"]++))
  done
done < <(git log --pretty=format:'%an%x09%s')

max_label_len=0
for t in "${types[@]}"; do
  count=${counts[$t]:-0}
  label="${t}: ${count}"
  len=${#label}
  (( len > max_label_len )) && max_label_len=$len
done

for t in "${types[@]}"; do
  count=${counts[$t]:-0}
  if (( count == 0 )); then
    continue
  fi
  color=${colors[$t]}
  printf "${color}%s: %d\e[0m" "$t" "$count"
  if [[ $show_contrib -eq 1 && $count -gt 0 ]]; then
    mapfile -t top_contribs < <(
      for k in "${!contrib_counts[@]}"; do
        [[ $k == "$t,"* ]] && echo "${contrib_counts[$k]} $k"
      done | sort -nr | head -n 3
    )
    if [[ ${#top_contribs[@]} -gt 0 ]]; then
      if [[ $show_list -eq 1 ]]; then
        printf "  $L_contrib_list"
      else
        pad=$((max_label_len - ${#t} - 2))
        if [ $count -gt 0 ]; then
          pad=$((pad - ${#count}))
        fi
        printf "%*s  $L_contrib" $pad ""
      fi
      first=1
      for entry in "${top_contribs[@]}"; do
        count_c=$(echo "$entry" | cut -d' ' -f1)
        name_c=$(echo "$entry" | cut -d' ' -f2- | cut -d',' -f2-)
        if [[ $first -eq 0 ]]; then printf ", "; fi
        printf "%s(%d)" "$name_c" "$count_c"
        first=0
      done
      printf "]"
    fi
  fi
  echo
  if [[ $show_list -eq 1 && $count -gt 0 ]]; then
    while IFS=$'\t' read -r author msg; do
      trimmed_msg=$(echo "$msg" | xargs -0)
      if [[ -n "$trimmed_msg" ]]; then
        if [[ $show_contrib -eq 1 ]]; then
          printf "${color}    %-*s - %s\e[0m\n" "$max_author_len" "$author" "$msg"
        else
          printf "${color}    %s\e[0m\n" "$msg"
        fi
      fi
    done <<< "${commits_by_type[$t]}"
  fi
done

echo -e "\e[1;37m$L_total: ${total}\e[0m"
