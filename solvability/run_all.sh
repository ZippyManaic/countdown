#!/bin/sh
# Rebuild every result in this directory from scratch on CPUs 0-23 in about six minutes
set -e
here=$(cd "$(dirname "$0")" && pwd)
data="$here/data"
mkdir -p "$data"
rustc --edition 2021 -O -o "$here/checker/reach" "$here/checker/reach.rs"
taskset -c 0-23 "$here/checker/reach" "$data/checker.tsv" 24 | gzip -9 > "$data/certificates.txt.gz"
taskset -c 0-23 "$here/checker/reach" "$data/checker_cats.tsv" 24 0,3,4 | gzip -9 > "$data/certificates_cats.txt.gz"
taskset -c 0-23 "$here/checker/reach" "$data/checker_nasty.tsv" 24 1,2,3,4 12,37,62,87 | gzip -9 > "$data/certificates_nasty.txt.gz"
"$here/csolve/run.sh" main
"$here/csolve/run.sh" cats
"$here/csolve/run.sh" nasty
gzip -9 -f "$data/c_values_cats.txt" "$data/c_values_nasty.txt"
cd "$here/scripts"
python3 compare.py > "$data/compare.txt"
python3 compare.py cats > "$data/compare_cats.txt"
python3 compare.py nasty > "$data/compare_nasty.txt"
python3 analyse.py > /dev/null
python3 analyse_cats.py > /dev/null
python3 analyse_nasty.py > /dev/null
python3 empirical.py > "$data/empirical.txt"
python3 verify_certificates.py > "$data/verify_certificates.txt"
python3 verify_certificates.py --answers > "$data/verify_answers.txt"
python3 verify_certificates.py "$data/certificates_cats.txt.gz" "$data/misses_cats.tsv" > "$data/verify_certificates_cats.txt"
python3 verify_certificates.py --c-texts "$data/c_values_cats.txt.gz" "$data/pools_cats.txt" "$data/misses_cats.tsv" > "$data/verify_c_cats.txt"
python3 verify_certificates.py "$data/certificates_nasty.txt.gz" "$data/misses_nasty.tsv" > "$data/verify_certificates_nasty.txt"
python3 verify_certificates.py --c-texts "$data/c_values_nasty.txt.gz" "$data/pools_nasty.txt" "$data/misses_nasty.tsv" > "$data/verify_c_nasty.txt"
python3 check_c_texts.py cats > "$data/check_c_texts.txt"
python3 check_c_texts.py nasty > "$data/check_c_texts_nasty.txt"
cat "$data"/compare*.txt "$data"/verify*.txt "$data"/check_c_texts*.txt "$data/empirical.txt"
