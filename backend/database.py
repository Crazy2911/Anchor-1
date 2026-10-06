import os
from pathlib import Path
from dotenv import load_dotenv
load_dotenv(
    Path(__file__).resolve().parent / ".env",
    override=False,
    interpolate=False,
)
import psycopg
from psycopg.rows import dict_row
import logging


def connect():
    database_url = os.environ.get("DATABASE_URL", "").strip()

    if not database_url:
        raise RuntimeError("DATABASE_URL is missing.")

    try:
        connection = psycopg.connect(
            database_url,
            row_factory=dict_row,
            connect_timeout=10,
            sslmode="require",
            prepare_threshold=None,
            application_name="anchor",
        )
    except psycopg.OperationalError as error:
        message = str(error).lower()

        if "password authentication failed" in message:
            reason = "Database username or password rejected."
        elif "tenant or user not found" in message:
            reason = "Pooler username or project reference is incorrect."
        elif "translate host name" in message or "name resolution" in message:
            reason = "Database hostname could not be resolved."
        elif "network is unreachable" in message:
            reason = "Database network address is unreachable."
        elif "timeout" in message or "timed out" in message:
            reason = "Database connection timed out."
        elif "connection refused" in message:
            reason = "Database host refused the connection."
        elif "ssl" in message or "certificate" in message:
            reason = "Database TLS connection failed."
        else:
            reason = "Database connection failed for an unclassified reason."

        logging.getLogger(__name__).error("%s", reason)
        raise

    try:
        # Applies only to this transaction, including through the pooler.
        connection.execute("SET LOCAL search_path TO anchor")
    except Exception:
        connection.close()
        raise

    return connection