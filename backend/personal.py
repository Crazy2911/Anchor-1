import datetime

from database import connect


MOODS = {
    "Great",
    "Good",
    "Okay",
    "Low",
    "Prefer not to say",
}


def text(data, key, minimum, maximum):
    if not isinstance(data, dict):
        raise ValueError("Expected a JSON object.")

    value = data.get(key)

    if not isinstance(value, str):
        raise ValueError(f"{key} must be text.")

    value = value.strip()

    if not minimum <= len(value) <= maximum:
        raise ValueError(
            f"{key} must contain {minimum}–{maximum} characters."
        )

    return value


def validate_id(value):
    if (
        not isinstance(value, str)
        or not 1 <= len(value) <= 80
        or not all(
            character.isalnum() or character in "-_"
            for character in value
        )
    ):
        raise ValueError("Invalid record ID.")

    return value


def read_data(user_id):
    with connect() as connection:
        # Read all personal records from a consistent snapshot.
        connection.execute(
            "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"
        )

        goals = connection.execute(
            """
            SELECT id, title, reason
            FROM user_goals
            WHERE user_id = %s
            ORDER BY id DESC
            """,
            (user_id,),
        ).fetchall()

        habits = connection.execute(
            """
            SELECT id, goal_id, title, completed_on
            FROM user_habits
            WHERE user_id = %s
            ORDER BY id DESC
            """,
            (user_id,),
        ).fetchall()

        reflections = connection.execute(
            """
            SELECT id, title, body, mood
            FROM user_reflections
            WHERE user_id = %s
            ORDER BY id DESC
            """,
            (user_id,),
        ).fetchall()

        profile = connection.execute(
            """
            SELECT accounts.display_name,
                   COALESCE(user_profiles.bio, '') AS bio,
                   COALESCE(user_profiles.region, '') AS region
            FROM accounts
            LEFT JOIN user_profiles
                ON user_profiles.user_id = accounts.id
            WHERE accounts.id = %s
            """,
            (user_id,),
        ).fetchone()

        if profile is None:
            raise ValueError("Account no longer exists.")

    return {
        "goals": [
            {
                "id": row["id"],
                "title": row["title"],
                "reason": row["reason"],
            }
            for row in goals
        ],
        "habits": [
            {
                "id": row["id"],
                "goalId": row["goal_id"],
                "title": row["title"],
                "completedOn": row["completed_on"],
            }
            for row in habits
        ],
        "reflections": [
            {
                "id": row["id"],
                "title": row["title"],
                "body": row["body"],
                "mood": row["mood"],
            }
            for row in reflections
        ],
        "profile": {
            "name": profile["display_name"],
            "bio": profile["bio"],
            "region": profile["region"],
        },
    }


def save_record(user_id, kind, record_id, data):
    validate_id(record_id)

    if kind not in {"goals", "habits", "reflections"}:
        raise ValueError("Unknown record type.")

    title = text(data, "title", 3, 100)

    if kind == "goals":
        reason = text(data, "reason", 10, 3000)

        with connect() as connection:
            connection.execute(
                """
                INSERT INTO user_goals (
                    user_id, id, title, reason
                )
                VALUES (%s, %s, %s, %s)
                ON CONFLICT (user_id, id)
                DO UPDATE SET
                    title = EXCLUDED.title,
                    reason = EXCLUDED.reason
                """,
                (user_id, record_id, title, reason),
            )

    elif kind == "habits":
        goal_id = validate_id(data.get("goalId"))
        completed_on = data.get("completedOn")

        if completed_on is not None:
            if not isinstance(completed_on, str):
                raise ValueError("Invalid completion date.")

            try:
                parsed = datetime.date.fromisoformat(completed_on)
            except ValueError:
                raise ValueError(
                    "Use a YYYY-MM-DD completion date."
                ) from None

            if parsed.isoformat() != completed_on:
                raise ValueError(
                    "Use a YYYY-MM-DD completion date."
                )

        with connect() as connection:
            # Prevent deletion of the linked goal during this save.
            goal = connection.execute(
                """
                SELECT id
                FROM user_goals
                WHERE user_id = %s AND id = %s
                FOR KEY SHARE
                """,
                (user_id, goal_id),
            ).fetchone()

            if goal is None:
                raise ValueError(
                    "Choose one of your existing goals."
                )

            connection.execute(
                """
                INSERT INTO user_habits (
                    user_id, id, goal_id, title, completed_on
                )
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (user_id, id)
                DO UPDATE SET
                    goal_id = EXCLUDED.goal_id,
                    title = EXCLUDED.title,
                    completed_on = EXCLUDED.completed_on
                """,
                (
                    user_id,
                    record_id,
                    goal_id,
                    title,
                    completed_on,
                ),
            )

    else:
        body = text(data, "body", 10, 3000)
        mood = text(data, "mood", 1, 40)

        if mood not in MOODS:
            raise ValueError("Choose a supported mood.")

        with connect() as connection:
            connection.execute(
                """
                INSERT INTO user_reflections (
                    user_id, id, title, body, mood
                )
                VALUES (%s, %s, %s, %s, %s)
                ON CONFLICT (user_id, id)
                DO UPDATE SET
                    title = EXCLUDED.title,
                    body = EXCLUDED.body,
                    mood = EXCLUDED.mood
                """,
                (user_id, record_id, title, body, mood),
            )

    return {"id": record_id, "saved": True}


def delete_record(user_id, kind, record_id):
    validate_id(record_id)

    # Complete queries are selected from a fixed mapping.
    queries = {
        "goals": """
            DELETE FROM user_goals
            WHERE user_id = %s AND id = %s
        """,
        "habits": """
            DELETE FROM user_habits
            WHERE user_id = %s AND id = %s
        """,
        "reflections": """
            DELETE FROM user_reflections
            WHERE user_id = %s AND id = %s
        """,
    }

    query = queries.get(kind)

    if query is None:
        raise ValueError("Unknown record type.")

    with connect() as connection:
        connection.execute(query, (user_id, record_id))

    return {"id": record_id, "deleted": True}


def save_profile(user_id, data):
    name = text(data, "name", 2, 40)
    bio = text(data, "bio", 0, 300)
    region = text(data, "region", 0, 60)

    with connect() as connection:
        account = connection.execute(
            """
            UPDATE accounts
            SET display_name = %s
            WHERE id = %s
            RETURNING id
            """,
            (name, user_id),
        ).fetchone()

        if account is None:
            raise ValueError("Account no longer exists.")

        connection.execute(
            """
            INSERT INTO user_profiles (user_id, bio, region)
            VALUES (%s, %s, %s)
            ON CONFLICT (user_id)
            DO UPDATE SET
                bio = EXCLUDED.bio,
                region = EXCLUDED.region
            """,
            (user_id, bio, region),
        )

        connection.execute(
            "UPDATE posts SET author = %s WHERE author_id = %s",
            (name, user_id),
        )

        connection.execute(
            "UPDATE comments SET author = %s WHERE author_id = %s",
            (name, user_id),
        )

    return {"saved": True}