usage() {
	cat <<EOF
git-commit-stats - Git提交统计工具（按作者和时间范围）
┌───────────────────────────────────────────────────────────────┐
│                    Git提交统计分析工具                         │
├───────────────────────────────────────────────────────────────┤
│  功能：统计指定作者的Git提交数据，包括提交次数、代码变更行数  │
│  特性：支持自定义时间范围、时区设置和多仓库统计               │
└───────────────────────────────────────────────────────────────┘

使用语法:
  git-commit-stats [选项]

参数选项:
  -r, --rows <天数>      设置统计天数范围（默认: 30天）
      --author <作者名>   指定Git作者名称（需与git log记录一致）
      --timezone <时区>  设置时区偏移量（格式: ±HHMM，默认: +0800）
  -R, --repo <路径>      指定Git仓库路径（可多次使用）
  -b, --branch <分支名>  指定统计的分支（默认: 当前分支）
  -h, --help             显示帮助信息

使用示例:
  1. 基本用法（统计当前作者30天数据）:
     git-commit-stats

  2. 统计特定作者90天数据:
     git-commit-stats --author john -r 90

  3. 跨时区统计（太平洋时间）:
     git-commit-stats --timezone "-0700"

  4. 多仓库统计:
     git-commit-stats -R ~/project1 -R ~/project2
输出格式说明:
  ┌──────────────┬────────────┬──────────┬──────────┬──────────────┐
  │ 日期         │ 提交次数   │ 添加行   │ 删除行   │ 净变化       │
  ├──────────────┼────────────┼──────────┼──────────┼──────────────┤
  │ 2025-07-01   │ 5          │ 120      │ 80       │ +40          │
  └──────────────┴────────────┴──────────┴──────────┴──────────────┘

提交频率颜色标识:
  • 0次    : 深灰色（低活跃）
  • 1次    : 淡蓝色（常规提交）
  • 2-3次  : 绿色（活跃）
  • 4-5次  : 亮黄色（高度活跃）
  • 6-10次 : 洋红色（非常活跃）
  • 11+次  : 闪烁红色（异常活跃）

注意事项:
  1. 必须在Git仓库目录或通过-R参数指定有效仓库路径
  2. 时区格式必须符合ISO 8601标准（如+0800表示东八区）
  3. 作者名称需与git log记录的完全一致（包括大小写）
  4. 统计结果包含非合并提交

版本信息: v1.0 | 维护者: oupasi | 更新日期: 2025-07-27
EOF
}
days=30
author="oupasi"
timezone="+0800"
repo="."  # 默认当前仓库
branch="main"    # 默认当前分支

# 解析命令行参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--rows)
      if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
        days=$2
        shift 2
      else
        echo "错误: -r 参数需要正整数" >&2
        exit 1
      fi
      ;;
    --author)
      if [[ -n "$2" ]]; then
        author=$2
        shift 2
      else
        echo "错误: --author 参数需要值" >&2
        exit 1
      fi
      ;;
    --timezone)
      if [[ -n "$2" ]]; then
        timezone=$2
        shift 2
      else
        echo "错误: --timezone 参数需要值（如+0800）" >&2
        exit 1
      fi
      ;;
    -R|--repo) 
      if [[ -n "$2" ]]; then
        repo="$2"
        shift 2
      else
        echo "错误: --repo 参数需要路径" >&2
        exit 1
      fi
      ;;
    -b|--branch) 
      if [[ -n "$2" ]]; then
        branch="$2"
        shift 2
      else
        echo "错误: --branch 参数需要分支名" >&2
        exit 1
      fi
      ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
      echo "未知参数: $1" >&2
      exit 1
      ;;
  esac
done

end_day=$((days - 1))
temp_file=$(mktemp)
repo=$(realpath "$repo")
git_dir="$repo/.git"

if ! git --git-dir="$git_dir" rev-parse --is-inside-work-tree &>/dev/null; then
    echo "错误: $git_dir 不是有效的Git仓库" >&2
    exit 1
fi

# 检查分支是否存在
if ! git --git-dir="$git_dir" show-ref --verify --quiet "refs/heads/$branch"; then
    echo "错误: 分支 '$branch' 在仓库 $repo 中不存在" >&2
    exit 1
fi

branch_cmd=""
[[ -n "$branch" ]] && branch_cmd="$branch"

for i in $(seq 0 $end_day); do
date=$(date -d "$i days ago" +%Y-%m-%d)

# 获取提交次数（支持外部仓库和分支）
commit_count=$(git --git-dir="$git_dir" rev-list --count --no-merges \
    --author="$author" \
    --since="$date 00:00:00 $timezone" \
    --until="$date 23:59:59 $timezone" \
    $branch_cmd)

# 获取代码变更统计
result=$(git --git-dir="$git_dir" log --author="$author" \
    --since="$date 00:00:00 $timezone" \
    --until="$date 23:59:59 $timezone" \
    $branch_cmd \
    --pretty=tformat: --numstat |
    awk '{ add += $1; subs += $2 }
        END { printf "%d\t%d\t%d", add, subs, add-subs }')

IFS=$'\t' read -r add subs net <<< "$result"

# 存储数据（新增仓库路径和分支列）
echo -e "$date\t$repo\t$branch\t$commit_count\t$add\t$subs\t$net" >> "$temp_file"
done

awk -F '\t' '
BEGIN {
    # 定义表格边框样式
    border_top = "┌──────────────┬────────────┬──────────┬──────────┬──────────────┐"
    border_header = "├──────────────┼────────────┼──────────┼──────────┼──────────────┤"
    border_bottom = "└──────────────┴────────────┴──────────┴──────────┴──────────────┘"

    # 定义提交次数的五级颜色序列
    color_0 = "\033[0;37m"    # 浅灰色（0次）
    color_1 = "\033[0;36m"    # 青色（1次）
    color_2_3 = "\033[0;32m"  # 绿色（2-3次）
    color_4_5 = "\033[1;32m"  # 亮绿色（4-5次）
    color_6_10 = "\033[1;36m" # 亮青色（6-10次）
    color_11plus = "\033[1;32;1m" # 高亮绿色（11次及以上）
    reset = "\033[0m"         # 颜色重置

    # 打印表头
    printf "Repository: \033[32m%s\033[0m  Branch: \033[32m%s\033[0m\n", "'"$repo"'", "'"$branch"'" 
    print border_top
    printf "│ \033[1;36m%-10s\033[0m │ \033[1;36m%-6s\033[0m │ \033[1;36m%-5s\033[0m │ \033[1;36m%-5s\033[0m │ \033[1;36m%-9s\033[0m │\n",
        "日期", "提交次数", "添加行", "删除行", "净变化"
    print border_header
}
{
    # 设置提交次数颜色 (五级序列)
    commit_count = $4
    if (commit_count == 0) commit_color = color_0
    else if (commit_count == 1) commit_color = color_1
    else if (commit_count >= 2 && commit_count <= 3) commit_color = color_2_3
    else if (commit_count >= 4 && commit_count <= 5) commit_color = color_4_5
    else if (commit_count >= 6 && commit_count <= 10) commit_color = color_6_10
    else commit_color = color_11plus  # 11次以上

    # 设置净变化值颜色
    net_color = ($7 > 0) ? "\033[32m" : ($7 < 0) ? "\033[31m" : "\033[33m"
    reset = "\033[0m"

    # 格式化输出每行数据
    printf "│ %-12s │ %s%-10d%s │ %8d │ %8d │ %s%-12s%s │\n",
            $1, 
            commit_color, commit_count, reset, 
            $5, $6, 
            net_color, $7, reset
}
END {
    print border_bottom
    # 显示统计天数
    printf "统计天数: \033[1;33m%d\033[0m  作者: \033[1;33m%s\033[0m\n", NR, "'"$author"'"
}
' "$temp_file"
rm -f "$temp_file"
