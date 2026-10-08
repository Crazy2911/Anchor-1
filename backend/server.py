import json
import logging
import os
import image_service
from storage_service import StorageError, create_signed_url
import people
import psycopg
from fastapi import Depends, FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException

import ai_service
import auth
import personal
import social

from pathlib import Path
from dotenv import load_dotenv
load_dotenv(
    Path(__file__).resolve().parent / ".env",
    override=False,
    interpolate=False,
)
from database import connect


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("anchor")

app = FastAPI(title="Anchor API", version="1.0.0")

# Match this with Flutter's fixed local web port.
# Set ALLOWED_ORIGINS to your frontend URL when deploying.
origins = [
    value.strip()
    for value in os.environ.get(
        "ALLOWED_ORIGINS",
        "http://localhost:3000,http://127.0.0.1:3000",
    ).split(",")
    if value.strip()
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "Accept"],
)

MAX_JSON_BYTES = 64 * 1024


# ---------------------------------------------------------------------------
# ERRORS AND REQUEST VALIDATION
# ---------------------------------------------------------------------------

def error_response(status, message):
    return JSONResponse(
        status_code=status,
        content={"message": message},
        headers={"Cache-Control": "no-store"},
    )


@app.exception_handler(auth.AuthError)
async def auth_error_handler(request, error):
    return error_response(error.status, error.message)


@app.exception_handler(ai_service.AIError)
async def ai_error_handler(request, error):
    return error_response(error.status, error.message)


@app.exception_handler(ValueError)
async def value_error_handler(request, error):
    return error_response(400, str(error))


@app.exception_handler(RequestValidationError)
async def validation_error_handler(request, error):
    return error_response(400, "Invalid request parameters.")


@app.exception_handler(HTTPException)
async def http_error_handler(request, error):
    message = (
        error.detail
        if isinstance(error.detail, str)
        else "The request could not be completed."
    )
    return error_response(error.status_code, message)


@app.exception_handler(psycopg.Error)
async def database_error_handler(request, error):
    # Avoid logging SQL parameters or private record contents.
    logger.error(
        "Database failure: %s; SQLSTATE=%s",
        type(error).__name__,
        error.sqlstate,
    )
    return error_response(
        503,
        "Database temporarily unavailable. Please try again.",
    )


@app.middleware("http")
async def no_cache(request, call_next):
    response = await call_next(request)
    response.headers["Cache-Control"] = "no-store"
    return response


async def json_body(request: Request):
    body = bytearray()

    async for chunk in request.stream():
        body.extend(chunk)

        if len(body) > MAX_JSON_BYTES:
            raise HTTPException(413, "Request body is too large.")

    if not body:
        raise ValueError("Request body is missing.")

    try:
        data = json.loads(body.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        raise ValueError("Expected a valid JSON request.") from None

    if not isinstance(data, dict):
        raise ValueError("Expected a JSON object.")

    return data


def require_user(request: Request):
    return auth.current_user(
        request.headers.get("Authorization")
    )
@app.exception_handler(StorageError)
async def storage_error_handler(request: Request, error: StorageError):
    return JSONResponse(
        status_code=error.status,
        content={"message": error.message},
        headers={"Cache-Control": "no-store"},
    )


async def read_image_upload(
    request: Request,
    user=Depends(require_user),
):
    content_type = (
        request.headers.get("content-type", "")
        .split(";", 1)[0]
        .strip()
        .lower()
    )

    if content_type not in {
        "image/jpeg",
        "image/png",
        "image/webp",
    }:
        raise StorageError(
            415, "Send a JPEG, PNG, or WebP image."
        )

    chunks = bytearray()

    async for chunk in request.stream():
        if len(chunks) + len(chunk) > image_service.MAX_INPUT_BYTES:
            raise StorageError(
                413, "Choose an image smaller than 2 MiB."
            )
        chunks.extend(chunk)

    if not chunks:
        raise StorageError(400, "Choose an image.")

    return user, bytes(chunks)


@app.post("/me/images", status_code=201)
def upload_community_image(upload=Depends(read_image_upload)):
    user, raw = upload
    return image_service.create_image(user["id"], raw)


def valid_id(value):
    return personal.validate_id(value)


def text_field(data, key, minimum, maximum):
    return personal.text(data, key, minimum, maximum)


# ---------------------------------------------------------------------------
# COMMUNITY READS
# ---------------------------------------------------------------------------

def read_posts(post_id=None):
    with connect() as connection:
        connection.execute(
            "SET TRANSACTION ISOLATION LEVEL REPEATABLE READ"
        )

        if post_id is None:
            posts = connection.execute(
                """
                SELECT id, author_id, author, title, body, topic
                FROM posts
                ORDER BY created_at DESC, id ASC
                """
            ).fetchall()

            comments = connection.execute(
                """
                SELECT id, post_id, author_id, author, body, parent_id
                FROM comments
                ORDER BY created_at ASC, id ASC
                """
            ).fetchall()
        else:
            posts = connection.execute(
                """
                SELECT id, author_id, author, title, body, topic
                FROM posts
                WHERE id = %s
                """,
                (post_id,),
            ).fetchall()

            comments = connection.execute(
                """
                SELECT id, post_id, author_id, author, body, parent_id
                FROM comments
                WHERE post_id = %s
                ORDER BY created_at ASC, id ASC
                """,
                (post_id,),
            ).fetchall()

    comments_by_post = {}

    for row in comments:
        comments_by_post.setdefault(row["post_id"], []).append({
            "id": row["id"],
            "authorId": row["author_id"],
            "author": row["author"],
            "body": row["body"],
            "parentId": row["parent_id"],
        })

    return [
        {
            "id": row["id"],
            "authorId": row["author_id"],
            "author": row["author"],
            "title": row["title"],
            "body": row["body"],
            "topic": row["topic"],
            "comments": comments_by_post.get(row["id"], []),
        }
        for row in posts
    ]


@app.get("/health")
def health():
    with connect() as connection:
        row = connection.execute(
            """
            SELECT
                (SELECT COUNT(*) FROM posts) AS posts,
                (SELECT COUNT(*) FROM comments) AS comments
            """
        ).fetchone()

    return {
        "status": "ok",
        "database": "postgresql",
        "posts": row["posts"],
        "comments": row["comments"],
    }


@app.get("/posts")
def get_posts():
    return {"posts": read_posts()}


# ---------------------------------------------------------------------------
# AUTHENTICATION
# ---------------------------------------------------------------------------

@app.post("/auth/register", status_code=201)
def register(data: dict = Depends(json_body)):
    return auth.register(data)


@app.post("/auth/login")
def login(data: dict = Depends(json_body)):
    return auth.login(data)


@app.get("/auth/me")
def get_current_user(user: dict = Depends(require_user)):
    return {"user": user}


@app.post("/auth/logout")
def logout(request: Request):
    return auth.logout(request.headers.get("Authorization"))


# ---------------------------------------------------------------------------
# PERSONAL DATA
# ---------------------------------------------------------------------------

@app.get("/me/data")
def get_personal_data(user: dict = Depends(require_user)):
    return personal.read_data(user["id"])


@app.put("/me/profile")
def update_profile(
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    return personal.save_profile(user["id"], data)


@app.put("/me/{kind}/{record_id}")
def save_personal_record(
    kind: str,
    record_id: str,
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    # Reports use the same URL shape as personal records.
    if kind == "reports":
        return social.report_post(
            user["id"], valid_id(record_id), data
        )

    if kind not in {"goals", "habits", "reflections"}:
        raise HTTPException(404, "Endpoint not found.")

    return personal.save_record(
        user["id"], kind, record_id, data
    )


@app.delete("/me/{kind}/{record_id}")
def delete_personal_record(
    kind: str,
    record_id: str,
    user: dict = Depends(require_user),
):
    if kind not in {"goals", "habits", "reflections"}:
        raise HTTPException(404, "Endpoint not found.")

    return personal.delete_record(
        user["id"], kind, record_id
    )


# ---------------------------------------------------------------------------
# SOCIAL PREFERENCES
# ---------------------------------------------------------------------------

@app.get("/me/social")
def get_social_state(user: dict = Depends(require_user)):
    return social.read_state(user["id"])


@app.put("/me/social")
def update_social_state(
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    return social.set_preference(user["id"], data)


# ---------------------------------------------------------------------------
# POSTS AND COMMENTS
# ---------------------------------------------------------------------------

@app.put("/posts/{post_id}")
def save_post(
    post_id: str,
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    valid_id(post_id)

    title = text_field(data, "title", 3, 100)
    body = text_field(data, "body", 10, 3000)
    topic = text_field(data, "topic", 1, 80)


    with connect() as connection:
        # Lock the account so profile updates and author labels
        # remain consistent during this write.
        account = connection.execute(
            """
            SELECT display_name
            FROM accounts
            WHERE id = %s
            FOR SHARE
            """,
            (user["id"],),
        ).fetchone()

        if account is None:
            raise auth.AuthError(401, "Please sign in again.")

        saved = connection.execute(
            """
            INSERT INTO posts (
                id, author_id, author, title, body, topic
            )
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (id)
            DO UPDATE SET
                author = EXCLUDED.author,
                title = EXCLUDED.title,
                body = EXCLUDED.body,
                topic = EXCLUDED.topic
            WHERE posts.author_id = EXCLUDED.author_id
            RETURNING id
            """,
            (
                post_id,
                user["id"],
                account["display_name"],
                title,
                body,
                topic,
            ),
        ).fetchone()

        if saved is None:
            raise HTTPException(
                403, "You can only edit your own posts."
            )

    return {"id": post_id, "saved": True}


@app.delete("/posts/{post_id}")
def delete_post(
    post_id: str,
    user: dict = Depends(require_user),
):
    valid_id(post_id)

    with connect() as connection:
        existing = connection.execute(
            """
            SELECT author_id
            FROM posts
            WHERE id = %s
            FOR UPDATE
            """,
            (post_id,),
        ).fetchone()

        if existing is not None:
            if existing["author_id"] != user["id"]:
                raise HTTPException(
                    403, "You can only delete your own posts."
                )

            connection.execute(
                "DELETE FROM posts WHERE id = %s",
                (post_id,),
            )

    return {"id": post_id, "deleted": True}


@app.put("/posts/{post_id}/comments/{comment_id}")
def add_comment(
    post_id: str,
    comment_id: str,
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    valid_id(post_id)
    valid_id(comment_id)

    body = text_field(data, "body", 3, 1000)
    parent_id = data.get("parentId")

    if parent_id is not None:
        valid_id(parent_id)

    with connect() as connection:
        account = connection.execute(
            """
            SELECT display_name
            FROM accounts
            WHERE id = %s
            FOR SHARE
            """,
            (user["id"],),
        ).fetchone()

        if account is None:
            raise auth.AuthError(401, "Please sign in again.")

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
            raise HTTPException(
                404, "This post no longer exists."
            )

        if parent_id is not None:
            parent = connection.execute(
                """
                SELECT parent_id
                FROM comments
                WHERE id = %s AND post_id = %s
                FOR KEY SHARE
                """,
                (parent_id, post_id),
            ).fetchone()

            if parent is None:
                raise ValueError("The original comment is missing.")

            if parent["parent_id"] is not None:
                raise ValueError("Reply to a top-level comment.")

        inserted = connection.execute(
            """
            INSERT INTO comments (
                id, post_id, author_id, author, body, parent_id
            )
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (id) DO NOTHING
            RETURNING id
            """,
            (
                comment_id,
                post_id,
                user["id"],
                account["display_name"],
                body,
                parent_id,
            ),
        ).fetchone()

        if inserted is None:
            existing = connection.execute(
                """
                SELECT post_id, author_id, body, parent_id
                FROM comments
                WHERE id = %s
                """,
                (comment_id,),
            ).fetchone()

            same_request = (
                existing is not None
                and existing["post_id"] == post_id
                and existing["author_id"] == user["id"]
                and existing["body"] == body
                and existing["parent_id"] == parent_id
            )

            if not same_request:
                raise HTTPException(
                    409, "Comment ID is already in use."
                )

    return {"id": comment_id, "saved": True}


# ---------------------------------------------------------------------------
# AI: EXISTING GROQ AND GEMINI FALLBACK
# ---------------------------------------------------------------------------

@app.post("/ai/reflect")
def reflect(
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    return ai_service.reflect(data)


@app.post("/ai/plan")
def plan(
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    goal = None

    if data.get("task") == "habit":
        goal_id = valid_id(data.get("goalId"))
        private_data = personal.read_data(user["id"])

        goal = next(
            (
                item
                for item in private_data["goals"]
                if item["id"] == goal_id
            ),
            None,
        )

        if goal is None:
            raise ValueError("Choose one of your existing goals.")

    return ai_service.plan(data, goal=goal)

@app.post("/ai/quote")
def generate_encouragement_quote(
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    return ai_service.generate_quote(data)
@app.post("/ai/improve-post")
def improve_post(
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    return ai_service.improve_post(data)


@app.post("/ai/summarize-discussion")
def summarize_discussion(
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    post_id = valid_id(data.get("postId"))
    posts = read_posts(post_id)

    if not posts:
        raise HTTPException(404, "This post no longer exists.")

    return ai_service.summarize_discussion(posts[0])


@app.post("/ai/next-action")
def next_action(
    user: dict = Depends(require_user),
    data: dict = Depends(json_body),
):
    habit_ids = data.get("habitIds")

    if not isinstance(habit_ids, list) or not 1 <= len(habit_ids) <= 20:
        raise ValueError("Choose 1–20 valid habits.")

    for habit_id in habit_ids:
        valid_id(habit_id)

    private_data = personal.read_data(user["id"])
    owned = {
        habit["id"]: habit
        for habit in private_data["habits"]
    }

    selected = []

    for habit_id in dict.fromkeys(habit_ids):
        habit = owned.get(habit_id)

        if habit is None:
            raise ValueError(
                "A selected habit no longer exists. Refresh first."
            )

        selected.append({
            "id": habit["id"],
            "title": habit["title"],
        })

    return ai_service.choose_next_action(selected)
@app.put("/posts/{post_id}/image")
def set_post_image(
    post_id: str,
    user=Depends(require_user),
    data=Depends(json_body),
):
    if "imageId" not in data:
        return JSONResponse(
            status_code=400,
            content={"message": "imageId is required."},
        )

    image_id = data["imageId"]

    if image_id is not None:
        if (
            not isinstance(image_id, str)
            or not image_id.strip()
            or len(image_id) > 80
        ):
            return JSONResponse(
                status_code=400,
                content={"message": "Invalid image ID."},
            )

    with connect() as connection:
        post = connection.execute(
            """
            SELECT id, author_id
            FROM posts
            WHERE id = %s
            FOR UPDATE
            """,
            (post_id,),
        ).fetchone()

        if post is None:
            return JSONResponse(
                status_code=404,
                content={"message": "This post no longer exists."},
            )

        if post["author_id"] != user["id"]:
            return JSONResponse(
                status_code=403,
                content={"message": "You can only edit your own posts."},
            )

        if image_id is not None:
            image = connection.execute(
                """
                SELECT id, owner_id, status
                FROM community_images
                WHERE id = %s
                FOR UPDATE
                """,
                (image_id,),
            ).fetchone()

            if (
                image is None
                or image["owner_id"] != user["id"]
                or image["status"] != "ready"
            ):
                return JSONResponse(
                    status_code=400,
                    content={
                        "message": "Choose one of your completed uploads."
                    },
                )

            linked_post = connection.execute(
                """
                SELECT id
                FROM posts
                WHERE image_id = %s AND id <> %s
                """,
                (image_id, post_id),
            ).fetchone()

            if linked_post is not None:
                return JSONResponse(
                    status_code=409,
                    content={
                        "message": "This image is already used by another post."
                    },
                )

        connection.execute(
            """
            UPDATE posts
            SET image_id = %s
            WHERE id = %s
            """,
            (image_id, post_id),
        )

    return {
        "postId": post_id,
        "imageId": image_id,
    }
@app.get("/posts/{post_id}/image")
def get_post_image(post_id: str):
    with connect() as connection:
        post = connection.execute(
            """
            SELECT
                p.id,
                i.id AS image_id,
                i.object_path
            FROM posts AS p
            LEFT JOIN community_images AS i
                ON i.id = p.image_id
                AND i.status = 'ready'
            WHERE p.id = %s
            """,
            (post_id,),
        ).fetchone()

    if post is None:
        return JSONResponse(
            status_code=404,
            content={"message": "This post no longer exists."},
        )

    if post["image_id"] is None:
        return {
            "postId": post_id,
            "imageId": None,
            "imageUrl": None,
            "expiresIn": 0,
        }

    image_url = create_signed_url(
        post["object_path"],
        expires_in=900,
    )

    return {
        "postId": post_id,
        "imageId": post["image_id"],
        "imageUrl": image_url,
        "expiresIn": 900,
    }
@app.exception_handler(people.PeopleError)
async def people_error_handler(
    request: Request,
    error: people.PeopleError,
):
    return JSONResponse(
        status_code=error.status,
        content={"message": error.message},
        headers={"Cache-Control": "no-store"},
    )


@app.get("/people/{person_id}")
def get_person_profile(
    person_id: str,
    user: dict = Depends(require_user),
):
    valid_id(person_id)

    return {
        "profile": people.read_profile(
            person_id,
            viewer_id=user["id"],
        ),
    }


@app.put("/people/{person_id}/follow")
def follow_person(
    person_id: str,
    user: dict = Depends(require_user),
):
    valid_id(person_id)

    return people.set_follow(
        viewer_id=user["id"],
        person_id=person_id,
        enabled=True,
    )


@app.delete("/people/{person_id}/follow")
def unfollow_person(
    person_id: str,
    user: dict = Depends(require_user),
):
    valid_id(person_id)

    return people.set_follow(
        viewer_id=user["id"],
        person_id=person_id,
        enabled=False,
    )
server.py