import sqlite3
import tempfile
import unittest

from pathlib import Path

import auth


class AuthenticationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)

        self.database = Path(self.directory.name) / "auth_test.db"
        auth.initialize_auth(self.database)

    def account_data(self):
        return {
            "username": "anchor_test",
            "displayName": "Anchor Test",
            "password": "A-test-password-123!",
        }

    def test_registration_login_and_logout(self):
        created = auth.register(
            self.database,
            self.account_data(),
        )

        self.assertEqual(
            created["user"]["username"],
            "anchor_test",
        )

        self.assertNotIn("password", created["user"])

        signed_in = auth.login(
            self.database,
            {
                "username": "anchor_test",
                "password": "A-test-password-123!",
            },
        )

        authorization = f"Bearer {signed_in['token']}"

        user = auth.current_user(
            self.database,
            authorization,
        )

        self.assertEqual(
            user["id"],
            created["user"]["id"],
        )

        auth.logout(
            self.database,
            authorization,
        )

        with self.assertRaises(auth.AuthError) as error:
            auth.current_user(
                self.database,
                authorization,
            )

        self.assertEqual(error.exception.status, 401)

    def test_wrong_password_is_rejected(self):
        auth.register(
            self.database,
            self.account_data(),
        )

        with self.assertRaises(auth.AuthError) as error:
            auth.login(
                self.database,
                {
                    "username": "anchor_test",
                    "password": "incorrect-password",
                },
            )

        self.assertEqual(error.exception.status, 401)

    def test_duplicate_username_is_rejected(self):
        auth.register(
            self.database,
            self.account_data(),
        )

        with self.assertRaises(auth.AuthError) as error:
            auth.register(
                self.database,
                self.account_data(),
            )

        self.assertEqual(error.exception.status, 409)

    def test_password_and_token_are_not_stored_as_plaintext(self):
        data = self.account_data()
        created = auth.register(self.database, data)

        connection = sqlite3.connect(self.database)

        try:
            stored_password = connection.execute(
                "SELECT password_hash FROM accounts"
            ).fetchone()[0]

            stored_token = connection.execute(
                "SELECT token_hash FROM sessions"
            ).fetchone()[0]
        finally:
            connection.close()

        self.assertNotEqual(
            stored_password,
            data["password"],
        )

        self.assertEqual(
            stored_token,
            auth.hash_token(created["token"]),
        )

        self.assertNotEqual(
            stored_token,
            created["token"],
        )

    def test_expired_session_is_rejected(self):
        created = auth.register(
            self.database,
            self.account_data(),
        )

        connection = sqlite3.connect(self.database)

        try:
            with connection:
                connection.execute(
                    "UPDATE sessions SET expires_at = 0"
                )
        finally:
            connection.close()

        with self.assertRaises(auth.AuthError) as error:
            auth.current_user(
                self.database,
                f"Bearer {created['token']}",
            )

        self.assertEqual(error.exception.status, 401)


if __name__ == "__main__":
    unittest.main(verbosity=2)