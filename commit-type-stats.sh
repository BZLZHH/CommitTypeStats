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
  L_opt_l="-l                       列出每个类型下的所有提交记录。"
  L_opt_c="-c                       显示每个类型的主要贡献者。"
  L_opt_prefix="-prefix <str>            设置提交类型的前缀 (可用'|'分隔多个)。默认不启用。"
  L_opt_suffix="-suffix <str>            设置提交类型的后缀 (可用'|'分隔多个)。默认为':|]|)'。"
  L_opt_no_prefix="--no-prefix              匹配时忽略前缀。"
  L_opt_no_suffix="--no-suffix              匹配时忽略后缀。"
  L_opt_project_name="-project-name <name>     手动设置项目名称 (覆盖自动检测)。"
  L_opt_project_root="-project-root <path>     手动设置项目根目录或远程仓库地址，远程可用 '#branch_or_tag' 指定分支/标签。"
  L_opt_no_cache="--no-cache               跳过缓存，临时克隆远程仓库（不会写入缓存）。"
  L_opt_clear="--clear                  清理缓存的 repos 并退出。"
  L_opt_help="-h, --help               显示此帮助信息。"
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
  L_opt_l="-l                       List all commit records under each type."
  L_opt_c="-c                       Show main contributors for each type."
  L_opt_prefix="-prefix <str>            Set commit type prefix (use '|' to separate multiple). Disabled by default."
  L_opt_suffix="-suffix <str>            Set commit type suffix (use '|' to separate multiple). Default: ':|]|)'."
  L_opt_no_prefix="--no-prefix              Ignore prefix when matching."
  L_opt_no_suffix="--no-suffix              Ignore suffix when matching."
  L_opt_project_name="-project-name <name>     Manually set the project name (overrides auto-detection)."
  L_opt_project_root="-project-root <path>     Manually set project root or remote git URL; use '#branch_or_tag' to specify branch/tag."
  L_opt_no_cache="--no-cache               Skip cache and do a temporary clone (won't write cache)."
  L_opt_clear="--clear                  Clear cached repos and exit."
  L_opt_help="-h, --help               Show this help message."
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
  if [[ "$url" =~ ^(git@|ssh://|http://|https://) || "$url" =~ ^[^/]+:[^/].+ ]]; then
    return 0
  fi
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

unsupported_args=()
valid_opts=( -l -c -prefix -suffix --no-prefix --no-suffix --no-cache --clear -project-name -project-root -h --help )

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
    *)
      arg="$1"
      matched=""
      for opt in "${valid_opts[@]}"; do
        if [[ "$arg" == "$opt" ]]; then matched="$opt"; break; fi
      done
      if [[ -z "$matched" && "$arg" == *s ]]; then
        base="${arg%?}"
        for opt in "${valid_opts[@]}"; do
          if [[ "$base" == "$opt" ]]; then matched="$opt"; break; fi
        done
      fi
      if [[ -z "$matched" ]]; then
        for opt in "${valid_opts[@]}"; do
          if [[ "${opt}s" == "$arg" ]]; then matched="$opt"; break; fi
        done
      fi
      if [[ -n "$matched" ]]; then
        set -- "$matched" "${@:2}"
        continue
      fi
      unsupported_args+=("$1")
      shift
      ;;
  esac
done

if [[ ${#unsupported_args[@]} -gt 0 ]]; then
  all_wrong_args=$(printf '%s ' "${unsupported_args[@]}")
  if [[ "$lang_code" == *"zh"* ]]; then
    echo "错误: 不支持的参数: ${all_wrong_args%?}。请使用 -h 或 --help 查看可用参数。" >&2
  else
    echo "Error: Unsupported argument(s): ${all_wrong_args%?}. Please use -h or --help to check available arguments" >&2
  fi
  exit 1
fi

cache_root="${XDG_CACHE_HOME:-$HOME/.cache}/commit-type-stats/repos"
if [[ $clear_cache -eq 1 ]]; then
  if [[ -d "$cache_root" ]]; then
    rm -rf "$cache_root"
    echo -e "\e[1;32m$L_cache_cleared: $cache_root\e[0m"
  else
    echo -e "\e[1;33m$L_cache_cleared: $cache_root (not exists)\e[0m"
  fi
  exit 0
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
          checkout_ref="${ref:-$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')}"
          if [[ -n "$checkout_ref" ]]; then
             git checkout --force "$checkout_ref" 2>/dev/null || git checkout --force "origin/$checkout_ref" 2>/dev/null || true
          fi
        fi
      fi
      if [[ ! -d "$cache_repo_dir/.git" ]]; then
        mkdir -p "$(dirname "$cache_repo_dir")"
        echo -e "\e[1;33m$L_cloning $cache_repo_dir\e[0m"
        clone_args=("$repo_url" "$cache_repo_dir")
        [[ -n "$ref" ]] && clone_args=("--branch" "$ref" "${clone_args[@]}")
        if ! git clone "${clone_args[@]}" 2>/dev/null; then
          echo "$L_clone_failed" >&2; rm -rf "$cache_repo_dir"; exit 1
        fi
      fi
      cd "$cache_repo_dir" || { echo "$L_cd_failed $cache_repo_dir" >&2; exit 1; }
      project_root="$cache_repo_dir"
      clean_tmp=0
    else
      echo -e "\e[1;33m$L_detect_remote $repo_url ${ref:+(#$ref)}\e[0m"
      tmpdir=$(mktemp -d)
      echo -e "\e[1;33m$L_cloning $tmpdir\e[0m"
      clone_args=("$repo_url" "$tmpdir")
      [[ -n "$ref" ]] && clone_args=("--branch" "$ref" "${clone_args[@]}")
      if ! git clone "${clone_args[@]}" 2>/dev/null; then
        echo "$L_clone_failed" >&2; rm -rf "$tmpdir"; exit 1
      fi
      cd "$tmpdir" || { echo "$L_cd_failed $tmpdir" >&2; rm -rf "$tmpdir"; exit 1; }
      project_root="$tmpdir"
      clean_tmp=1
    fi
  else
    cd "$project_root" 2>/dev/null || { echo "$L_cd_failed $project_root" >&2; exit 1; }
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
  [Feat]='\e[38;5;82m' [Chore]='\e[38;5;220m' [Fix]='\e[38;5;208m'
  [Improvement]='\e[38;5;39m' [Perf]='\e[38;5;33m' [Misc]='\e[38;5;141m'
  [Docs]='\e[38;5;250m' [Refactor]='\e[38;5;45m' [Update/Add]='\e[38;5;51m'
  [Adjust]='\e[38;5;99m' [Translate]='\e[38;5;213m' [Revert/Reapply]='\e[38;5;196m'
  [Merge]='\e[38;5;50m' [Others]='\e[38;5;244m'
)

read -r -d '' awk_script <<'EOF'
function escape_regex(str) {
    gsub(/[\\[.*+?(){}^$|]/, "\\\\&", str);
    return str;
}
BEGIN {
    FS="\t";
    SUBSEP = ",";
    split(types_list, types_arr, " ");
    for(i in types_arr) type_lookup[types_arr[i]] = 1;
    split(prefix_str, prefixes, "|");
    if (prefix_str == "") prefixes[1] = "";
    split(suffix_str, suffixes, "|");
    if (suffix_str == "") suffixes[1] = "";
}
{
    author = $1;
    line = $2;
    total++;
    if (length(author) > max_author_len) max_author_len = length(author);
    matches = "";
    matched_in_line = 0;
    if (match(line, /^(Revert|Reapply)/)) {
        matches = "Revert/Reapply";
        matched_in_line = 1;
    } else if (match(line, /^Merge/)) {
        matches = "Merge";
        matched_in_line = 1;
    }
    if (!matched_in_line) {
        content_to_parse = "";
        found = 0;
        for (p_idx in prefixes) {
            p = prefixes[p_idx];
            for (s_idx in suffixes) {
                s = suffixes[s_idx];
                temp = line;
                p_re = escape_regex(p);
                s_re = escape_regex(s);
                if (p != "" && s != "" && index(temp, p) && index(temp, s)) {
                    sub(".*" p_re, "", temp); sub(s_re ".*", "", temp); content_to_parse = temp; found = 1; break;
                } else if (p != "" && s == "" && index(temp, p)) {
                    sub(".*" p_re, "", temp); content_to_parse = temp; found = 1; break;
                } else if (p == "" && s != "" && index(temp, s)) {
                    sub(s_re ".*", "", temp); content_to_parse = temp; found = 1; break;
                } else if (p == "" && s == "") {
                    content_to_parse = temp; found = 1; break;
                }
            }
            if (found) break;
        }
        if (content_to_parse != "") {
            split(content_to_parse, parts, "|");
            for (i in parts) {
                part = parts[i];
                gsub(/^[[:space:]]+|[[:space:]]+$/, "", part);
                part_lower = tolower(part);
                for (j in types_arr) {
                    type_keyword = types_arr[j];
                    type_keyword_lower = tolower(type_keyword);
                    is_match = 0;
                    if (type_keyword == "Update/Add") {
                        if (index(part_lower, "update") || index(part_lower, "add")) is_match = 1;
                    } else if (type_keyword == "Improvement") {
                        if (index(part_lower, "improve")) is_match = 1;
                    } else {
                        if (index(part_lower, type_keyword_lower)) is_match = 1;
                    }
                    if (is_match && !(type_keyword in found_matches)) {
                        matches = matches (matches == "" ? "" : " ") type_keyword;
                        found_matches[type_keyword] = 1;
                    }
                }
            }
            delete found_matches;
        }
    }
    if (matches == "") matches = "Others";
    split(matches, found_types, " ");
    for (i in found_types) {
        t = found_types[i];
        if (t in type_lookup) {
            counts[t]++;
            contrib_counts[t,author]++;
            if (show_list_flag) {
                current_commit_author = author;
                current_commit_line = line;
                gsub(/\t/, "\\t", current_commit_author); gsub(/\n/, "\\n", current_commit_author);
                gsub(/\t/, "\\t", current_commit_line); gsub(/\n/, "\\n", current_commit_line);
                commits_by_type[t] = commits_by_type[t] current_commit_author "\t" current_commit_line "\n";
            }
        }
    }
}
END {
    print "total\t" total;
    print "maxlen\t" max_author_len;
    for (type in counts) {
        print "count\t" type "\t" counts[type];
    }
    for (key in contrib_counts) {
        split(key, parts, SUBSEP);
        print "contrib\t" parts[1] "\t" parts[2] "\t" contrib_counts[key];
    }
    if (show_list_flag) {
        for (type in commits_by_type) {
            gsub(/\n/, "\\n", commits_by_type[type]);
            print "commits\t" type "\t" commits_by_type[type];
        }
    }
}
EOF

declare -A counts
declare -A contrib_data
declare -A commits_by_type
total=0
max_author_len=0

processed_output=$(git log --pretty=format:'%an%x09%s' | awk \
    -v show_list_flag="$show_list" \
    -v prefix_str="$prefix" \
    -v suffix_str="$suffix" \
    -v types_list="${types[*]}" \
    "$awk_script")

while IFS= read -r line; do
    key=$(echo "$line" | cut -f1 -d$'\t')
    case "$key" in
        total)
            total=$(echo "$line" | cut -f2 -d$'\t') ;;
        maxlen)
            max_author_len=$(echo "$line" | cut -f2 -d$'\t') ;;
        count)
            type=$(echo "$line" | cut -f2 -d$'\t')
            count=$(echo "$line" | cut -f3 -d$'\t')
            counts["$type"]="$count"
            ;;
        contrib)
            type=$(echo "$line" | cut -f2 -d$'\t')
            author=$(echo "$line" | cut -f3 -d$'\t')
            count=$(echo "$line" | cut -f4 -d$'\t')
            contrib_data["$type"]+="${count} ${author}"$'\n'
            ;;
        commits)
            type=$(echo "$line" | cut -f2 -d$'\t')
            content=$(echo "$line" | cut -f3- -d$'\t')
            commits_by_type["$type"]=$(printf '%b' "${content//\\n/\\n}")
            ;;
    esac
done <<< "$processed_output"

max_label_len=0
for t in "${types[@]}"; do
  count=${counts[$t]:-0}
  [[ $count -eq 0 ]] && continue
  label="${t}: ${count}"
  len=${#label}
  (( len > max_label_len )) && max_label_len=$len
done

for t in "${types[@]}"; do
  count=${counts[$t]:-0}
  [[ $count -eq 0 ]] && continue

  color=${colors[$t]}
  printf "${color}%s: %d\e[0m" "$t" "$count"

  if [[ $show_contrib -eq 1 ]]; then
    if [[ -n "${contrib_data[$t]}" ]]; then
      mapfile -t top_contribs < <(printf '%s' "${contrib_data[$t]}" | sort -rnb | head -n 9)

      if [[ ${#top_contribs[@]} -gt 0 ]]; then
        if [[ $show_list -eq 1 ]]; then
          printf "  %s" "$L_contrib_list"
        else
          pad=$((max_label_len - ${#t} - ${#count} - 2))
          printf "%*s  %s" $pad "" "$L_contrib"
        fi

        first=1
        for entry in "${top_contribs[@]}"; do
          read -r count_c name_c <<< "$entry"
          [[ $first -eq 0 ]] && printf ", "
          printf "%s(%d)" "$name_c" "$count_c"
          first=0
        done
        printf "]"
      fi
    fi
  fi
  echo

  if [[ $show_list -eq 1 && -n "${commits_by_type[$t]}" ]]; then
    while IFS=$'\t' read -r author msg; do
      [[ -z "$msg" ]] && continue
      if [[ $show_contrib -eq 1 ]]; then
        printf "${color}    %-*s - %s\e[0m\n" "$max_author_len" "$author" "$msg"
      else
        printf "${color}    %s\e[0m\n" "$msg"
      fi
    done <<< "${commits_by_type[$t]}"
  fi
done

echo -e "\e[1;37m$L_total: ${total}\e[0m"
if [[ $show_contrib -eq 1 ]]; then
  if [[ $show_list -eq 1 ]]; then
    printf "\e[1;37m%s" "$L_contrib_list"
    mapfile -t all_contribs < <(git shortlog -s -n --no-merges | sed -e 's/^[[:space:]]*//')
    first=1
    for entry in "${all_contribs[@]}"; do
      count=$(printf '%s' "$entry" | awk '{print $1}')
      name=$(printf '%s' "$entry" | cut -f2- -d$'	')
      if [[ -z "$name" ]]; then name=$(printf '%s' "$entry" | cut -d' ' -f2-); fi
      [[ $first -eq 0 ]] && printf ", "
      printf "%s(%s)" "$name" "$count"
      first=0
    done
    printf "]\e[0m
"
  else
    printf "\e[1;37m%s" "$L_contrib"
    mapfile -t top_contribs < <(git shortlog -s -n --no-merges | sed -e 's/^[[:space:]]*//' | head -n 9)
    first=1
    for entry in "${top_contribs[@]}"; do
      count=$(printf '%s' "$entry" | awk '{print $1}')
      name=$(printf '%s' "$entry" | cut -f2- -d$'	')
      if [[ -z "$name" ]]; then name=$(printf '%s' "$entry" | cut -d' ' -f2-); fi
      [[ $first -eq 0 ]] && printf ", "
      printf "%s(%s)" "$name" "$count"
      first=0
    done
    printf "]\e[0m
"
  fi
fi
