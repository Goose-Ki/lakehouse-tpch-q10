-- Часть 2. Запускай ПО ШАГАМ в интерактивной консоли:
--   docker exec -it trino trino --catalog lakehouse
-- Скопируй из вывода нужные snapshot_id вместо <SNAPSHOT_ID>.

-- ===== A. Schema evolution на Silver =====

-- A1. Схема до изменений
DESCRIBE lakehouse.silver.customer_nation;

-- A2. Добавляем колонку: старые файлы не переписываются, для них segment = NULL
ALTER TABLE lakehouse.silver.customer_nation ADD COLUMN segment varchar;
SELECT custkey, name, segment FROM lakehouse.silver.customer_nation LIMIT 5;

-- A3. Заполняем новую колонку из Bronze
MERGE INTO lakehouse.silver.customer_nation AS t
USING lakehouse.bronze.customer AS s
  ON t.custkey = s.custkey
WHEN MATCHED THEN UPDATE SET segment = s.mktsegment;
SELECT segment, count(*) FROM lakehouse.silver.customer_nation GROUP BY segment;

-- A4. Переименование: Iceberg хранит колонки по id, данные не переписываются
ALTER TABLE lakehouse.silver.customer_nation RENAME COLUMN phone TO phone_number;
DESCRIBE lakehouse.silver.customer_nation;

-- A5. Возвращаем имя обратно, чтобы 03_gold.sql продолжал работать
ALTER TABLE lakehouse.silver.customer_nation RENAME COLUMN phone_number TO phone;

-- ===== B. Time travel и восстановление =====

-- B1. История снапшотов: каждая операция выше = новый снапшот
SELECT snapshot_id, committed_at, operation
FROM lakehouse.silver."customer_nation$snapshots"
ORDER BY committed_at;

-- B2. «Авария»: случайно удалили всех клиентов из Германии
SELECT count(*) FROM lakehouse.silver.customer_nation WHERE nation = 'GERMANY';
DELETE FROM lakehouse.silver.customer_nation WHERE nation = 'GERMANY';
SELECT count(*) FROM lakehouse.silver.customer_nation WHERE nation = 'GERMANY';   -- 0

-- B3. Читаем таблицу на момент ДО удаления (возьми предпоследний snapshot_id из B1/повтори B1)
SELECT count(*) FROM lakehouse.silver.customer_nation FOR VERSION AS OF <SNAPSHOT_ID>
WHERE nation = 'GERMANY';

-- B4. Скрипт восстановления: дописываем потерянные строки из старого снапшота
INSERT INTO lakehouse.silver.customer_nation
SELECT * FROM lakehouse.silver.customer_nation FOR VERSION AS OF <SNAPSHOT_ID>
WHERE nation = 'GERMANY';

SELECT count(*) FROM lakehouse.silver.customer_nation WHERE nation = 'GERMANY';   -- как в B2 до удаления

-- B5. Финальная история: видно delete и последующий append
SELECT snapshot_id, committed_at, operation
FROM lakehouse.silver."customer_nation$snapshots"
ORDER BY committed_at;
