-- SILVER: очищенные и обогащённые данные, только нужные запросу колонки.

DROP TABLE IF EXISTS lakehouse.silver.customer_nation;
DROP TABLE IF EXISTS lakehouse.silver.returned_lines;

-- 1) Клиент, обогащённый названием страны (джойн customer ⋈ nation).
--    Справочник: 150 тыс. строк при sf1, партиционирование не нужно.
CREATE TABLE lakehouse.silver.customer_nation
WITH (format = 'PARQUET') AS
SELECT
  c.custkey,
  trim(c.name)    AS name,
  trim(c.address) AS address,
  c.phone,
  c.acctbal,
  c.comment,
  n.name          AS nation
FROM lakehouse.bronze.customer AS c
JOIN lakehouse.bronze.nation   AS n ON c.nationkey = n.nationkey
WHERE c.custkey IS NOT NULL;

-- 2) Факт «возвращённые позиции»: lineitem ⋈ orders, только returnflag = 'R',
--    с заранее посчитанной выручкой строки. Все даты (а не только Q4-1993) —
--    чтобы слой годился и для других периодов; срез по кварталу делает Gold.
--    Партиционирование по году. Возвраты (returnflag = 'R') в TPC-H есть только
--    у позиций, полученных до 1995-06-17, поэтому партиций 4 (1992–1995),
--    ~450 тыс. строк в каждой полной. По месяцу вышло бы ~40 мелких файлов.
CREATE TABLE lakehouse.silver.returned_lines
WITH (format = 'PARQUET', partitioning = ARRAY['year(orderdate)']) AS
SELECT
  l.orderkey,
  l.linenumber,
  o.custkey,
  o.orderdate,
  l.extendedprice,
  l.discount,
  l.extendedprice * (1 - l.discount) AS net_revenue
FROM lakehouse.bronze.lineitem AS l
JOIN lakehouse.bronze.orders   AS o ON l.orderkey = o.orderkey
WHERE l.returnflag = 'R'
  AND l.extendedprice > 0
  AND l.discount BETWEEN 0 AND 1;
