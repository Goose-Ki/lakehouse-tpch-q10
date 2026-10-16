-- 1) Сверка Gold с эталонным Q10 прямо по tpch.sf1. Ожидаем 0 и 0.
WITH ref AS (
  SELECT c.custkey, sum(l.extendedprice * (1 - l.discount)) AS revenue
  FROM tpch.sf1.customer AS c
  JOIN tpch.sf1.orders   AS o ON c.custkey = o.custkey
  JOIN tpch.sf1.lineitem AS l ON l.orderkey = o.orderkey
  WHERE o.orderdate >= DATE '1993-10-01' AND o.orderdate < DATE '1994-01-01'
    AND l.returnflag = 'R'
  GROUP BY c.custkey
  ORDER BY revenue DESC
  LIMIT 20
),
gold AS (SELECT custkey, revenue FROM lakehouse.gold.top20_returned_customers)
SELECT
  (SELECT count(*) FROM (SELECT custkey, round(revenue, 2) FROM ref
                         EXCEPT SELECT custkey, round(revenue, 2) FROM gold) AS a) AS only_in_reference,
  (SELECT count(*) FROM (SELECT custkey, round(revenue, 2) FROM gold
                         EXCEPT SELECT custkey, round(revenue, 2) FROM ref) AS b) AS only_in_gold;

-- 2) Строки и вес каждой таблицы — для таблиц раздела 4 отчёта.
SELECT 'bronze.customer' AS tbl, (SELECT count(*) FROM lakehouse.bronze.customer) AS row_cnt,
       (SELECT round(sum(file_size_in_bytes) / 1048576.0, 2) FROM lakehouse.bronze."customer$files") AS size_mb
UNION ALL
SELECT 'bronze.orders', (SELECT count(*) FROM lakehouse.bronze.orders),
       (SELECT round(sum(file_size_in_bytes) / 1048576.0, 2) FROM lakehouse.bronze."orders$files")
UNION ALL
SELECT 'bronze.lineitem', (SELECT count(*) FROM lakehouse.bronze.lineitem),
       (SELECT round(sum(file_size_in_bytes) / 1048576.0, 2) FROM lakehouse.bronze."lineitem$files")
UNION ALL
SELECT 'bronze.nation', (SELECT count(*) FROM lakehouse.bronze.nation),
       (SELECT round(sum(file_size_in_bytes) / 1048576.0, 2) FROM lakehouse.bronze."nation$files")
UNION ALL
SELECT 'silver.customer_nation', (SELECT count(*) FROM lakehouse.silver.customer_nation),
       (SELECT round(sum(file_size_in_bytes) / 1048576.0, 2) FROM lakehouse.silver."customer_nation$files")
UNION ALL
SELECT 'silver.returned_lines', (SELECT count(*) FROM lakehouse.silver.returned_lines),
       (SELECT round(sum(file_size_in_bytes) / 1048576.0, 2) FROM lakehouse.silver."returned_lines$files")
UNION ALL
SELECT 'gold.top20_returned_customers', (SELECT count(*) FROM lakehouse.gold.top20_returned_customers),
       (SELECT round(sum(file_size_in_bytes) / 1048576.0, 2) FROM lakehouse.gold."top20_returned_customers$files");

-- 3) Партиции Silver — подтверждение, что партиционирование по году сработало.
SELECT partition, record_count, file_count, total_size
FROM lakehouse.silver."returned_lines$partitions"
ORDER BY 1;
