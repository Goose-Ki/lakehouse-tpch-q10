#!/usr/bin/env bash
# Бенчмарк форматов и кодеков на Bronze: для каждой пары ФОРМАТ:КОДЕК пересоздаёт
# 4 таблицы Bronze в отдельной схеме bench_<формат>_<кодек>, меряет время записи,
# размер и время Q10.
# Запуск: ./bench.sh
#         COMBOS="PARQUET:GZIP PARQUET:ZSTD" RUNS=5 ./bench.sh
set -euo pipefail

SF="${SF:-sf1}"
COMBOS="${COMBOS:-PARQUET:GZIP PARQUET:ZSTD PARQUET:SNAPPY PARQUET:NONE ORC:GZIP ORC:ZSTD}"
RUNS="${RUNS:-5}"
OUT="results/bench.md"
mkdir -p results

now()   { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
diff_s(){ perl -e "printf '%.2f', $2 - $1"; }
trino_q() { docker exec trino trino --catalog lakehouse --output-format TSV "$@"; }

q10_sql() {   # $1 = схема, $2 = метка для поиска в system.runtime.queries
cat <<SQL
SELECT /* $2 */ c.custkey, c.name, sum(l.extendedprice * (1 - l.discount)) AS revenue,
       c.acctbal, n.name AS nation, c.address, c.phone, c.comment
FROM lakehouse.$1.customer AS c
JOIN lakehouse.$1.orders   AS o ON c.custkey = o.custkey
JOIN lakehouse.$1.lineitem AS l ON l.orderkey = o.orderkey
JOIN lakehouse.$1.nation   AS n ON c.nationkey = n.nationkey
WHERE o.orderdate >= DATE '1993-10-01' AND o.orderdate < DATE '1994-01-01'
  AND l.returnflag = 'R'
GROUP BY c.custkey, c.name, c.acctbal, n.name, c.address, c.phone, c.comment
ORDER BY revenue DESC
LIMIT 20
SQL
}

{
  echo "Масштаб: $SF, прогонов Q10 на кодек: $RUNS, время Q10 — по system.runtime.queries"
  echo
  echo "| Формат | Кодек | Запись Bronze, с | Размер Bronze, МБ | lineitem, МБ | Q10 прогоны, с | Q10 медиана, с |"
  echo "|---|---|---|---|---|---|---|"
} > "$OUT"

for combo in $COMBOS; do
  fmt="${combo%%:*}"; codec="${combo##*:}"
  s="bench_$(echo "${fmt}_${codec}" | tr '[:upper:]' '[:lower:]')"
  echo ">>> $fmt + $codec -> lakehouse.$s"

  trino_q --execute "CREATE SCHEMA IF NOT EXISTS lakehouse.$s"
  for t in customer orders lineitem nation; do
    trino_q --execute "DROP TABLE IF EXISTS lakehouse.$s.$t"
  done

  # 1) Запись
  t0=$(now)
  trino_q --session "lakehouse.compression_codec=$codec" --execute "
    CREATE TABLE lakehouse.$s.customer WITH (format='$fmt') AS SELECT * FROM tpch.$SF.customer;
    CREATE TABLE lakehouse.$s.orders   WITH (format='$fmt') AS SELECT * FROM tpch.$SF.orders;
    CREATE TABLE lakehouse.$s.lineitem WITH (format='$fmt') AS SELECT * FROM tpch.$SF.lineitem;
    CREATE TABLE lakehouse.$s.nation   WITH (format='$fmt') AS SELECT * FROM tpch.$SF.nation;" > /dev/null
  t1=$(now)
  write_s=$(diff_s "$t0" "$t1")

  # 2) Размер (только data-файлы Iceberg)
  size_mb=$(trino_q --execute "
    SELECT round(sum(file_size_in_bytes) / 1048576.0, 2) FROM (
      SELECT file_size_in_bytes FROM lakehouse.$s.\"customer\$files\" UNION ALL
      SELECT file_size_in_bytes FROM lakehouse.$s.\"orders\$files\"   UNION ALL
      SELECT file_size_in_bytes FROM lakehouse.$s.\"lineitem\$files\" UNION ALL
      SELECT file_size_in_bytes FROM lakehouse.$s.\"nation\$files\")" | tr -d '"')
  li_mb=$(trino_q --execute "SELECT round(sum(file_size_in_bytes) / 1048576.0, 2) FROM lakehouse.$s.\"lineitem\$files\"" | tr -d '"')

  # 3) Q10: прогрев + RUNS замеров
  trino_q --execute "$(q10_sql "$s" "warmup_$s")" > /dev/null
  for i in $(seq 1 "$RUNS"); do
    trino_q --execute "$(q10_sql "$s" "bench_q10_${s}_run$i")" > /dev/null
  done
  times=$(trino_q --execute "
    SELECT round(date_diff('millisecond', created, \"end\") / 1000.0, 3)
    FROM system.runtime.queries
    WHERE query LIKE '%bench_q10_${s}_run%'
      AND query NOT LIKE '%system.runtime%'
      AND state = 'FINISHED'
    ORDER BY created" | tr -d '"')
  runs_list=$(echo "$times" | paste -sd ',' - | sed 's/,/, /g')
  median=$(echo "$times" | sort -n | awk '{a[NR]=$1} END {print a[int((NR+1)/2)]}')

  echo "| $fmt | $codec | $write_s | $size_mb | $li_mb | $runs_list | $median |" >> "$OUT"
  echo "    запись ${write_s}s, размер ${size_mb} МБ, Q10 медиана ${median}s"
done

echo
cat "$OUT"
