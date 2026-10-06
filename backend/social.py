import secrets

from database import connect


TOPICS = {
    "Study routines",
    "Creative practice",
    "Digital habits",
    "Everyday wellbeing",
}

REPORT_REASONS = {
    "Spam",
    "Harassment",
    "Personal information",
    "Unsafe advice",
}


def read_state(user_id):
    with connect() as connection:
        connection.execute(
            "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"
        )

        saves = connection.execute(
            """
            SELECT post_id
            FROM saved_posts
            WHERE user_id = %s
            ORDER BY post_id
            """,
            (user_id,),
        ).fetchall()

        helpful = connection.execute(
            """
            SELECT post_id
            FROM helpful_posts
            WHERE user_id = %s
            ORDER BY post_id
            """,
            (user_id,),
        ).fetchall()

        followed = connection.execute(
            """
            SELECT topic
            FROM followed_topics
            WHERE user_id = %s
            ORDER BY topic
            """,
            (user_id,),
        ).fetchall()

    return {
        "savedPostIds": [row["post_id"] for row in saves],
        "helpfulPostIds": [row["post_id"] for row in helpful],
        "followedTopics": [row["topic"] for row in followed],
    }


def set_preference(user_id, data):
    if not isinstance(data, dict):
        raise ValueError("Expected a JSON object.")

    kind = data.get("kind")
    target = data.get("target")
    enabled = data.get("enabled")

    if not isinstance(kind, str):
        raise ValueError("Invalid preference type.")

    if not isinstance(target, str) or not target.strip():
        raise ValueError("A target is required.")

    target = target.strip()

    if len(target) > 100:
        raise ValueError("Target is too long.")

    if not isinstance(enabled, bool):
        raise ValueError("enabled must be true or false.")

    # SQL identifiers come only from this fixed mapping.
    mapping = {
        "save": ("saved_posts", "post_id"),
        "helpful": ("helpful_posts", "post_id"),
        "topic": ("followed_topics", "topic"),
    }

    if kind not in mapping:
        raise ValueError("Unknown preference type.")

    table, column = mapping[kind]

    if kind == "topic" and len(target) > 80:
        raise ValueError("Topic must contain 1–80 characters.")

    with connect() as connection:
        if enabled and kind in {"save", "helpful"}:
            # Prevent the post disappearing during this transaction.
            post = connection.execute(
                """
                SELECT id
                FROM posts
                WHERE id = %s
                FOR KEY SHARE
                """,
                (target,),
            ).fetchone()

            if post is None:
                raise ValueError("This post no longer exists.")

        if enabled:
            connection.execute(
                f"""
                INSERT INTO {table} (user_id, {column})
                VALUES (%s, %s)
                ON CONFLICT (user_id, {column}) DO NOTHING
                """,
                (user_id, target),
            )
        else:
            connection.execute(
                f"""
                DELETE FROM {table}
                WHERE user_id = %s AND {column} = %s
                """,
                (user_id, target),
            )

    return {
        "kind": kind,
        "target": target,
        "enabled": enabled,
    }


def report_post(user_id, post_id, data):
    if not isinstance(data, dict):
        raise ValueError("Expected a JSON object.")

    if (
        not isinstance(post_id, str)
        or not 1 <= len(post_id) <= 80
        or not all(
            character.isalnum() or character in "-_"
            for character in post_id
        )
    ):
        raise ValueError("Invalid post ID.")

    reason = data.get("reason")

    if not isinstance(reason, str) or reason not in REPORT_REASONS:
        raise ValueError("Choose a supported report reason.")

    with connect() as connection:
        post = connection.execute(
            """
            SELECT id
            FROM posts
            WHERE id = %s
            FOR KEY SHARE
            """,
            (post_id,),
        ).fetchone()

        if post is None:
            raise ValueError("This post no longer exists.")

        # Repeated submissions preserve the first report.
        connection.execute(
            """
            INSERT INTO content_reports (
                id, reporter_id, post_id, reason
            )
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (reporter_id, post_id) DO NOTHING
            """,
            (
                secrets.token_hex(16),
                user_id,
                post_id,
                reason,
            ),
        )

    return {"recorded": True}