#!/usr/bin/env bash
#
# Helpers for the flag-table drift test ('flag-table-drift.bats'): extract the normalized
# '(short, long)' flag pairs from each of the three places a flag is declared, and compare
# two sets. Every extractor takes its input as an argument (a file path, or help text on
# stdin) so the test can point it at a deliberately drifted temp copy.
#
# A normalized pair is one line, '<short>,<long>': '-D,--flatten-dirs', or ',--toc' for a
# long-only flag. Value placeholders are dropped. Output is sorted. Only bash-3.2-safe
# constructs and POSIX 'sed'/'awk' (BSD awk included) are used.

# flag_pairs_from_parser <parse-options.sh>
# The rows of 'MD2X_OPTION_TABLE' ('short|long|kind|VARIABLE', '-' meaning no short flag).
flag_pairs_from_parser() {
  awk '
    /^MD2X_OPTION_TABLE=\(/ { in_table = 1; next }
    in_table && /^\)/ { in_table = 0 }
    in_table && /^[[:space:]]*'"'"'/ {
      row = $0
      sub(/^[[:space:]]*'"'"'/, "", row)
      sub(/'"'"'[[:space:]]*$/, "", row)
      n = split(row, f, "|")
      if (n < 4) { print "MALFORMED ROW: " $0; next }
      print (f[1] == "-" ? "" : "-" f[1]) ",--" f[2]
    }
  ' "$1" | sort
}

# flag_pairs_from_help   (help text on stdin)
# The option lines of the 'Options:' block: '  -D, --flatten-dirs ...' or '      --toc ...'.
flag_pairs_from_help() {
  awk '
    /^Options:[[:space:]]*$/ { in_opts = 1; next }
    in_opts && /^[[:space:]]*$/ { in_opts = 0 }
    in_opts && /^  -[A-Za-z], --[A-Za-z]/ {
      short = $1; sub(/,$/, "", short)
      print short "," $2
      next
    }
    in_opts && /^      --[A-Za-z]/ { print "," $1 }
  ' | sort
}

# flag_pairs_from_readme <README.md>
# The rows of the table under '## CLI reference': the first cell holds the backticked short
# and/or long flag, optionally followed by a value placeholder (`-o`, `--output <file>`).
flag_pairs_from_readme() {
  awk -F'|' '
    /^## / { in_ref = ($0 == "## CLI reference"); next }
    /^### / { in_ref = 0 }
    in_ref && /^\| `/ {
      short = ""; long = ""
      n = split($2, parts, "`")
      for (i = 2; i <= n; i += 2) {
        split(parts[i], w, " ")
        if (w[1] ~ /^--/) long = w[1]
        else if (w[1] ~ /^-[A-Za-z]$/) short = w[1]
      }
      if (long == "") print "MALFORMED ROW: " $0
      else print short "," long
    }
  ' "$1" | sort
}

# spec_flag_table_rows <spec.md>
# Prints any table row whose first cell is a backticked flag: a row-style flag table. The
# spec must have none (it links to the README table instead).
spec_flag_table_rows() {
  awk -F'|' '/^\|/ && $2 ~ /`--?[A-Za-z]/ { print }' "$1"
}

# flag_sets_compare <label-a> <file-a> <label-b> <file-b>
# Status 0 when the two sorted pair files are identical; otherwise prints which flags are
# present in one source but missing from the other, plus the raw diff, and returns 1.
flag_sets_compare() {
  local label_a="$1" file_a="$2" label_b="$3" file_b="$4"
  local only_a only_b
  if diff -q "${file_a}" "${file_b}" > /dev/null; then
    return 0
  fi
  only_a="$(comm -23 "${file_a}" "${file_b}")"
  only_b="$(comm -13 "${file_a}" "${file_b}")"
  printf 'flag table drift: %s and %s disagree\n' "${label_a}" "${label_b}"
  [[ -z "${only_a}" ]] || printf 'in %s but missing from %s:\n%s\n' "${label_a}" "${label_b}" "${only_a}"
  [[ -z "${only_b}" ]] || printf 'in %s but missing from %s:\n%s\n' "${label_b}" "${label_a}" "${only_b}"
  printf 'diff (< %s, > %s):\n' "${label_a}" "${label_b}"
  diff "${file_a}" "${file_b}" || true
  return 1
}
