# Superset + драйвер Trino (в базовом образе драйверов БД нет)
FROM apache/superset:6.0.0
USER root
RUN uv pip install --python /app/.venv/bin/python trino
USER superset
