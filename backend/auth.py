import hashlib
import hmac
import re
import secrets
import time

from psycopg.errors import UniqueViolation

from database import connect


SESSION_DURATION_SECONDS = 12 * 60 * 60
PASSWORD_ITERATIONS = 600_000

USERNAME_PATTERN = re.compile(r"^[a-z0-9_]{3,30}$")


class AuthError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def hash_password(password, salt):
    return hashlib.pbkdf2_hmac(
        "sha256",
        password.encode("utf-8"),
        bytes.fromhex(salt),
        PASSWORD_ITERATIONS,
    ).hex()


def hash_token(token):
    return hashlib.sha256(
        token.encode("utf-8")
    ).hexdigest()


def public_user(row):
    return {
        "id": row["id"],
        "username": row["username"],
        "displayName": row["display_name"],
    }


def required_text(data, key, minimum, maximum, strip=True):
    if not isinstance(data, dict):
        raise AuthError(400, "Expected a JSON object.")

    value = data.get(key)

    if not isinstance(value, str):
        raise AuthError(400, f"{key} must be text.")

    if strip:
        value = value.strip()

    if not minimum <= len(value) <= maximum:
        raise AuthError(
            400,
            f"{key} must contain {minimum}–{maximum} characters.",
        )

    return value


def issue_session(connection, user_id):
    token = secrets.token_urlsafe(32)
    now = int(time.time())
    expires_at = now + SESSION_DURATION_SECONDS

    connection.execute(
        "DELETE FROM sessions WHERE expires_at <= %s",
        (now,),
    )

    connection.execute(
        """
        INSERT INTO sessions (
            token_hash,
            user_id,
            expires_at
        )
        VALUES (%s, %s, %s)
        """,
        (hash_token(token), user_id, expires_at),
    )

    return token, expires_at


def register(data):
    username = required_text(
        data, "username", 3, 30
    ).lower()

    if not USERNAME_PATTERN.fullmatch(username):
        raise AuthError(
            400,
            "Username can contain lowercase letters, "
            "numbers, and underscores.",
        )

    display_name = required_text(
        data, "displayName", 2, 40
    )

    # Preserve intentional spaces in passwords.
    password = required_text(
        data, "password", 12, 128, strip=False
    )

    user_id = secrets.token_hex(16)
    salt = secrets.token_hex(16)
    password_digest = hash_password(password, salt)

    try:
        with connect() as connection:
            connection.execute(
                """
                INSERT INTO accounts (
                    id,
                    username,
                    display_name,
                    password_salt,
                    password_hash,
                    created_at
                )
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                (
                    user_id,
                    username,
                    display_name,
                    salt,
                    password_digest,
                    int(time.time()),
                ),
            )

            token, expires_at = issue_session(
                connection, user_id
            )

    except UniqueViolation as error:
        if error.diag.constraint_name == "accounts_username_key":
            raise AuthError(
                409,
                "That username is unavailable.",
            ) from None

        raise

    return {
        "token": token,
        "expiresAt": expires_at,
        "user": {
            "id": user_id,
            "username": username,
            "displayName": display_name,
        },
    }


def login(data):
    username = required_text(
        data, "username", 3, 30
    ).lower()

    password = required_text(
        data, "password", 1, 128, strip=False
    )

    with connect() as connection:
        account = connection.execute(
            """
            SELECT id,
                   username,
                   display_name,
                   password_salt,
                   password_hash
            FROM accounts
            WHERE username = %s
            """,
            (username,),
        ).fetchone()

        # Hash even for an unknown username.
        salt = (
            account["password_salt"]
            if account is not None
            else "00" * 16
        )

        candidate = hash_password(password, salt)

        expected = (
            account["password_hash"]
            if account is not None
            else "00" * 32
        )

        password_matches = hmac.compare_digest(
            candidate, expected
        )

        if account is None or not password_matches:
            raise AuthError(
                401,
                "Incorrect username or password.",
            )

        token, expires_at = issue_session(
            connection, account["id"]
        )

        result = {
            "token": token,
            "expiresAt": expires_at,
            "user": public_user(account),
        }

    return result


def bearer_token(authorization):
    if not isinstance(authorization, str):
        raise AuthError(401, "Please sign in.")

    parts = authorization.split()

    if (
        len(parts) != 2
        or parts[0].lower() != "bearer"
        or not 20 <= len(parts[1]) <= 200
    ):
        raise AuthError(401, "Please sign in.")

    return parts[1]


def current_user(authorization):
    token = bearer_token(authorization)

    with connect() as connection:
        row = connection.execute(
            """
            SELECT accounts.id,
                   accounts.username,
                   accounts.display_name
            FROM sessions
            JOIN accounts ON accounts.id = sessions.user_id
            WHERE sessions.token_hash = %s
              AND sessions.expires_at > %s
            """,
            (hash_token(token), int(time.time())),
        ).fetchone()

    if row is None:
        raise AuthError(
            401,
            "Your session has expired or is invalid. "
            "Please sign in.",
        )

    return public_user(row)


def logout(authorization):
    token = bearer_token(authorization)

    with connect() as connection:
        connection.execute(
            "DELETE FROM sessions WHERE token_hash = %s",
            (hash_token(token),),
        )

    return {"signedOut": True}