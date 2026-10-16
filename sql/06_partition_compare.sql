-- Обоснование партиционирования Silver цифрами.
-- Делаем копию returned_lines БЕЗ партиций и сравниваем, сколько данных читает
-- запрос Gold по каждой из версий.
-- Запуск: docker exec trino trino --session lakehouse.compression_codec=ZSTD --file /sql/06_partition_compare.sql

DROP TABLE IF EXISTS lakehouse.silver.returned_lines_nopart;
CREATE TABLE lakehouse.silver.returned_lines_nopart WITH (format = 'PARQUET') AS
SELECT * FROM lakehouse.silver.returned_lines;

-- Файлы и размер обеих версий
SELECT 'partitioned by year' AS variant, count(*) AS files, round(sum(file_size_in_bytes) / 1048576.0, 2) AS size_mb
FROM lakehouse.silver."returned_lines$files"
UNION ALL
SELECT 'no partitions', count(*), round(sum(file_size_in_bytes) / 1048576.0, 2)
FROM lakehouse.silver."returned_lines_nopart$files";

-- С партициями: смотри в выводе строку ScanFilterProject по returned_lines —
-- «Input: N rows (X MB)» и число splits.
EXPLAIN ANALYZE
SELECT r.custkey, sum(r.net_revenue)
FROM lakehouse.silver.returned_lines AS r
WHERE r.orderdate >= DATE '1993-10-01' AND r.orderdate < DATE '1994-01-01'
GROUP BY r.custkey;

-- Без партиций: тот же запрос, сравни Input rows / MB
EXPLAIN ANALYZE
SELECT r.custkey, sum(r.net_revenue)
FROM lakehouse.silver.returned_lines_nopart AS r
WHERE r.orderdate >= DATE '1993-10-01' AND r.orderdate < DATE '1994-01-01'
GROUP BY r.custkey;

DROP TABLE lakehouse.silver.returned_lines_nopart;
