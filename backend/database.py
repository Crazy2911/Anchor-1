import os

import psycopg
from psycopg.rows import dict_row


def connect():
    database_url = os.environ.get("DATABASE_URL", "").strip()

    if not database_url:
        raise RuntimeError("DATABASE_URL is missing.")

    connection = psycopg.connect(
        database_url,
        row_factory=dict_row,
        connect_timeout=10,
        sslmode="require",
        prepare_threshold=None,
        application_name="anchor",
    )

    try:
        # Applies only to this transaction, including through the pooler.
        connection.execute("SET LOCAL search_path TO anchor")
    except Exception:
        connection.close()
        raise

    return connection