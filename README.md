# Практическая №1 — локальный Lakehouse, вариант 2 (TPC-H Q10 «Returned Item Reporting»)

Стек: **MinIO** (S3) + **PostgreSQL** (метаданные каталога) + **Lakekeeper** (Iceberg REST Catalog) + **Trino** (SQL).
Масштаб: **sf1**. Отчёт — в `отчет.md`.

## Структура

```
docker-compose.yml              весь стек одной командой
lakekeeper/create-warehouse.json  warehouse Lakekeeper поверх бакета MinIO
trino/catalog/                  каталоги Trino: lakehouse (Iceberg) и tpch (генератор)
sql/00_schemas.sql              схемы bronze / silver / gold
sql/01_bronze.sql               сырые customer, orders, lineitem, nation
sql/02_silver.sql               customer_nation + returned_lines (партиции по году)
sql/03_gold.sql                 top20_returned_customers — ответ на Q10
sql/04_check.sql                сверка Gold с эталоном + строки/вес таблиц + партиции
sql/05_evolution_timetravel.sql часть 2: schema evolution и восстановление из снапшота
sql/06_partition_compare.sql    замер: Silver с партициями по году vs без партиций
bench.sh                        бенчмарк Parquet (GZIP/ZSTD/SNAPPY/NONE) и ORC (GZIP/ZSTD)
results/                        сюда bench.sh пишет таблицу результатов
```

## Запуск

0. Docker Desktop → Settings → Resources: **Memory ≥ 6 ГБ** (лучше 8).

1. Поднять стек:
   ```bash
   docker compose up -d
   docker compose ps -a                 # minio, postgres, lakekeeper, trino — Up; *-init и migrate — Exited (0)
   docker logs lakekeeper-init          # в ответе warehouse должен быть "warehouse-id"
   docker logs trino 2>&1 | grep "SERVER STARTED"
   ```

2. Проверить Trino и генератор:
   ```bash
   docker exec trino trino --execute "SHOW CATALOGS"                          # lakehouse, system, tpch
   docker exec trino trino --execute "SELECT count(*) FROM tpch.sf1.lineitem" # 6001215
   ```

3. Построить медальон:
   ```bash
   docker exec trino trino --file /sql/00_schemas.sql
   docker exec trino trino --session lakehouse.compression_codec=ZSTD --file /sql/01_bronze.sql
   docker exec trino trino --session lakehouse.compression_codec=ZSTD --file /sql/02_silver.sql
   docker exec trino trino --session lakehouse.compression_codec=ZSTD --file /sql/03_gold.sql
   docker exec trino trino --execute "SELECT * FROM lakehouse.gold.top20_returned_customers ORDER BY revenue DESC"
   ```

4. Проверки и цифры для отчёта:
   ```bash
   docker exec trino trino --file /sql/04_check.sql
   ```
   Первая строка должна быть `"0","0"` — Gold совпадает с эталонным Q10.

5. Замер партиционирования Silver:
   ```bash
   docker exec trino trino --session lakehouse.compression_codec=ZSTD --file /sql/06_partition_compare.sql > results/partition_compare.txt
   ```

6. Бенчмарк форматов и кодеков (~5–10 минут):
   ```bash
   ./bench.sh
   cat results/bench.md
   ```

7. Часть 2 — интерактивно, по шагам из `sql/05_evolution_timetravel.sql`:
   ```bash
   docker exec -it trino trino --catalog lakehouse
   ```

## Веб-интерфейсы

| Сервис | Адрес | Логин / пароль |
|---|---|---|
| MinIO (Silo) Console | http://localhost:9001 | minio / minio12345 |
| Lakekeeper UI | http://localhost:8181/ui | — |
| Trino UI | http://localhost:8080 | любое имя, без пароля |

## Остановка

```bash
docker compose stop        # пауза, данные сохраняются
docker compose down -v     # удалить всё вместе с данными
```

## Если что-то пошло не так

- **Порт 9001 занят** — поменяй в compose `"9001:9001"` на `"19001:9001"`.
- **`lakekeeper` долго unhealthy** — `docker logs lakekeeper`. Если ошибка про БД — `docker compose down -v && docker compose up -d`.
- **В логах `lakekeeper-init` ошибка про warehouse** — посмотри текст: чаще всего бакет не создался (`docker logs lakehouse-minio-init`).
  При повторном `up` ошибка «already exists» — это нормально.
- **Trino: `Schema ... not found` / ошибки S3** — проверь, что `lakekeeper-init` отработал раньше Trino: `docker compose restart trino`.
- **Trino падает по памяти на bench** — увеличь память Docker Desktop.
