-- BRONZE: сырые таблицы TPC-H «как пришли», все колонки, без партиционирования.
-- Кодек задаётся при запуске: --session lakehouse.compression_codec=ZSTD
-- Масштаб: sf1 (если меняешь — замени во всех файлах).

DROP TABLE IF EXISTS lakehouse.bronze.customer;
DROP TABLE IF EXISTS lakehouse.bronze.orders;
DROP TABLE IF EXISTS lakehouse.bronze.lineitem;
DROP TABLE IF EXISTS lakehouse.bronze.nation;

CREATE TABLE lakehouse.bronze.customer WITH (format = 'PARQUET') AS SELECT * FROM tpch.sf1.customer;
CREATE TABLE lakehouse.bronze.orders   WITH (format = 'PARQUET') AS SELECT * FROM tpch.sf1.orders;
CREATE TABLE lakehouse.bronze.lineitem WITH (format = 'PARQUET') AS SELECT * FROM tpch.sf1.lineitem;
CREATE TABLE lakehouse.bronze.nation   WITH (format = 'PARQUET') AS SELECT * FROM tpch.sf1.nation;
