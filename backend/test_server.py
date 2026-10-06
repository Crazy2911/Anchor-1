import json
import tempfile
import threading
import unittest

from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

import server as api


class AnchorApiTests(unittest.TestCase):
    def setUp(self):
        self.original_database_path = api.DATABASE_PATH

        self.temporary_directory = tempfile.TemporaryDirectory()

        api.DATABASE_PATH = (
            Path(self.temporary_directory.name) / "test_anchor.db"
        )

        # Cleanup also runs if setup or a test fails.
        self.addCleanup(self.temporary_directory.cleanup)
        self.addCleanup(
            setattr,
            api,
            "DATABASE_PATH",
            self.original_database_path,
        )

        api.initialize_database()

        # Port 0 selects an available port automatically.
        self.http_server = api.ThreadingHTTPServer(
            ("127.0.0.1", 0),
            api.AnchorHandler,
        )

        self.server_thread = threading.Thread(
            target=self.http_server.serve_forever,
            daemon=True,
        )

        self.server_thread.start()
        self.addCleanup(self.stop_server)

        port = self.http_server.server_address[1]
        self.base_url = f"http://127.0.0.1:{port}"

    def stop_server(self):
        self.http_server.shutdown()
        self.http_server.server_close()
        self.server_thread.join(timeout=5)

    def request(self, method, path, body=None):
        payload = None
        headers = {"Accept": "application/json"}

        if body is not None:
            payload = json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"

        request = Request(
            f"{self.base_url}{path}",
            data=payload,
            headers=headers,
            method=method,
        )

        try:
            with urlopen(request, timeout=5) as response:
                return (
                    response.status,
                    json.loads(response.read().decode("utf-8")),
                )

        except HTTPError as error:
            with error:
                return (
                    error.code,
                    json.loads(error.read().decode("utf-8")),
                )

    def sample_post(self, title="Testing a small daily routine"):
        return {
            "author": "Test User",
            "title": title,
            "body": (
                "I am trying a short daily practice session "
                "and would like to compare experiences."
            ),
            "topic": "Study routines",
        }

    def create_post(self, post_id="test-post"):
        status, response = self.request(
            "PUT",
            f"/posts/{post_id}",
            self.sample_post(),
        )

        self.assertEqual(status, 200)
        self.assertTrue(response["saved"])

        return post_id

    def get_posts(self):
        status, response = self.request("GET", "/posts")

        self.assertEqual(status, 200)
        return response["posts"]

    def test_health_confirms_database_connection(self):
        status, response = self.request("GET", "/health")

        self.assertEqual(status, 200)
        self.assertEqual(response["status"], "ok")
        self.assertEqual(response["database"], "sqlite")
        self.assertEqual(response["posts"], 3)
        self.assertEqual(response["comments"], 1)

    def test_create_and_edit_post(self):
        post_id = self.create_post()

        created = next(
            post for post in self.get_posts()
            if post["id"] == post_id
        )

        self.assertEqual(created["authorId"], "me")
        self.assertEqual(
            created["title"],
            "Testing a small daily routine",
        )

        status, _ = self.request(
            "PUT",
            f"/posts/{post_id}",
            self.sample_post(title="My updated routine"),
        )

        self.assertEqual(status, 200)

        matching_posts = [
            post for post in self.get_posts()
            if post["id"] == post_id
        ]

        self.assertEqual(len(matching_posts), 1)
        self.assertEqual(
            matching_posts[0]["title"],
            "My updated routine",
        )

    def test_retrying_same_post_does_not_duplicate_it(self):
        body = self.sample_post()

        for _ in range(2):
            status, _ = self.request(
                "PUT",
                "/posts/retry-post",
                body,
            )

            self.assertEqual(status, 200)

        matching_posts = [
            post for post in self.get_posts()
            if post["id"] == "retry-post"
        ]

        self.assertEqual(len(matching_posts), 1)

    def test_invalid_post_is_not_saved(self):
        body = self.sample_post()
        body["title"] = "x"

        status, _ = self.request(
            "PUT",
            "/posts/invalid-post",
            body,
        )

        self.assertEqual(status, 400)

        self.assertFalse(
            any(
                post["id"] == "invalid-post"
                for post in self.get_posts()
            )
        )

    def test_cannot_edit_or_delete_another_authors_post(self):
        edit_status, _ = self.request(
            "PUT",
            "/posts/api-p1",
            self.sample_post(),
        )

        delete_status, _ = self.request(
            "DELETE",
            "/posts/api-p1",
        )

        self.assertEqual(edit_status, 403)
        self.assertEqual(delete_status, 403)

        self.assertTrue(
            any(
                post["id"] == "api-p1"
                for post in self.get_posts()
            )
        )

    def test_comments_replies_and_delete_cascade(self):
        post_id = self.create_post()

        status, _ = self.request(
            "PUT",
            f"/posts/{post_id}/comments/test-comment",
            {
                "author": "Test User",
                "body": "Starting with five minutes helped me.",
                "parentId": None,
            },
        )

        self.assertEqual(status, 200)

        reply = {
            "author": "Test User",
            "body": "I will try that smaller first step.",
            "parentId": "test-comment",
        }

        # Repeat the same reply request to verify safe retries.
        for _ in range(2):
            status, _ = self.request(
                "PUT",
                f"/posts/{post_id}/comments/test-reply",
                reply,
            )

            self.assertEqual(status, 200)

        post = next(
            post for post in self.get_posts()
            if post["id"] == post_id
        )

        self.assertEqual(len(post["comments"]), 2)

        saved_reply = next(
            comment for comment in post["comments"]
            if comment["id"] == "test-reply"
        )

        self.assertEqual(
            saved_reply["parentId"],
            "test-comment",
        )

        # Repeating a delete is safe too.
        for _ in range(2):
            status, _ = self.request(
                "DELETE",
                f"/posts/{post_id}",
            )

            self.assertEqual(status, 200)

        self.assertFalse(
            any(
                post["id"] == post_id
                for post in self.get_posts()
            )
        )

        # Check the database directly: the comments must also be gone.
        connection = api.connect_database()

        try:
            remaining = connection.execute(
                """
                SELECT COUNT(*)
                FROM comments
                WHERE post_id = ?
                """,
                (post_id,),
            ).fetchone()[0]

            self.assertEqual(remaining, 0)
        finally:
            connection.close()

    def test_reply_cannot_reference_another_posts_comment(self):
        post_id = self.create_post()

        # api-c1 belongs to api-p1, not this new post.
        status, _ = self.request(
            "PUT",
            f"/posts/{post_id}/comments/wrong-parent",
            {
                "author": "Test User",
                "body": "This reply points to a different discussion.",
                "parentId": "api-c1",
            },
        )

        self.assertEqual(status, 400)

        post = next(
            post for post in self.get_posts()
            if post["id"] == post_id
        )

        self.assertEqual(post["comments"], [])

    def test_data_survives_database_reinitialization(self):
        post_id = self.create_post("persistent-post")

        # This is the initialization called when the server starts again.
        api.initialize_database()

        posts = self.get_posts()

        self.assertEqual(len(posts), 4)

        self.assertEqual(
            sum(post["id"] == post_id for post in posts),
            1,
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)