from database import connect


class PeopleError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def read_profile(person_id, viewer_id):
    with connect() as connection:
        row = connection.execute(
            """
            SELECT
                a.id,
                a.username,
                a.display_name,
                COALESCE(p.bio, '') AS bio,

                (
                    SELECT COUNT(*)
                    FROM user_follows
                    WHERE following_id = a.id
                ) AS follower_count,

                (
                    SELECT COUNT(*)
                    FROM user_follows
                    WHERE follower_id = a.id
                ) AS following_count,

                (
                    SELECT COUNT(*)
                    FROM posts
                    WHERE author_id = a.id
                ) AS post_count,

                EXISTS (
                    SELECT 1
                    FROM user_follows
                    WHERE follower_id = %s
                      AND following_id = a.id
                ) AS is_following

            FROM accounts AS a
            LEFT JOIN user_profiles AS p
                ON p.user_id = a.id
            WHERE a.id = %s
            """,
            (viewer_id, person_id),
        ).fetchone()

    if row is None:
        raise PeopleError(404, "This account is no longer available.")

    return {
        "id": row["id"],
        "username": row["username"],
        "displayName": row["display_name"],
        "bio": row["bio"],
        "followerCount": row["follower_count"],
        "followingCount": row["following_count"],
        "postCount": row["post_count"],
        "isFollowing": row["is_following"],
        "isMe": row["id"] == viewer_id,
    }


def set_follow(viewer_id, person_id, enabled):
    if viewer_id == person_id:
        raise PeopleError(400, "You cannot follow yourself.")

    with connect() as connection:
        # Prevent either account being deleted during this operation.
        accounts = connection.execute(
            """
            SELECT id
            FROM accounts
            WHERE id IN (%s, %s)
            ORDER BY id
            FOR KEY SHARE
            """,
            (viewer_id, person_id),
        ).fetchall()

        account_ids = {row["id"] for row in accounts}

        if viewer_id not in account_ids:
            raise PeopleError(401, "Please sign in again.")

        if person_id not in account_ids:
            raise PeopleError(404, "This account is no longer available.")

        if enabled:
            connection.execute(
                """
                INSERT INTO user_follows (follower_id, following_id)
                VALUES (%s, %s)
                ON CONFLICT (follower_id, following_id) DO NOTHING
                """,
                (viewer_id, person_id),
            )
        else:
            connection.execute(
                """
                DELETE FROM user_follows
                WHERE follower_id = %s
                  AND following_id = %s
                """,
                (viewer_id, person_id),
            )

    return {
        "personId": person_id,
        "following": enabled,
    }