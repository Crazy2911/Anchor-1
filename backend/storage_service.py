import os
import re
from urllib.parse import quote, urlsplit

import httpx


MAX_IMAGE_BYTES = 2 * 1024 * 1024

ALLOWED_CONTENT_TYPES = {
    "image/jpeg",
    "image/png",
    "image/webp",
}


class StorageError(Exception):
    def __init__(self, status, message):
        super().__init__(message)
        self.status = status
        self.message = message


def _configuration():
    root = os.environ.get("SUPABASE_URL", "").strip().rstrip("/")
    key = os.environ.get("SUPABASE_SECRET_KEY", "").strip()
    bucket = os.environ.get(
        "SUPABASE_STORAGE_BUCKET", ""
    ).strip()

    if not root or not key or not bucket:
        raise StorageError(
            503,
            "Image storage is not configured on the server.",
        )

    parsed = urlsplit(root)

    if (
        parsed.scheme != "https"
        or not parsed.netloc
        or parsed.username
        or parsed.password
        or parsed.path
        or parsed.query
        or parsed.fragment
    ):
        raise StorageError(503, "Invalid storage project URL.")

    return root, key, bucket


def _object_path(path):
    if not isinstance(path, str) or not path or len(path) > 300:
        raise StorageError(400, "Invalid image path.")

    parts = path.split("/")

    if any(
        part in {"", ".", ".."}
        or not re.fullmatch(r"[A-Za-z0-9_.-]+", part)
        for part in parts
    ):
        raise StorageError(400, "Invalid image path.")

    return quote(path, safe="/")


def _request(method, suffix, *, content=None, json=None, headers=None):
    root, key, _ = _configuration()

    request_headers = {
        "apikey": key,
        "Accept": "application/json",
    }

    if headers:
        request_headers.update(headers)

    try:
        with httpx.Client(
            timeout=httpx.Timeout(30.0, connect=10.0),
            follow_redirects=False,
        ) as client:
            response = client.request(
                method,
                f"{root}/storage/v1{suffix}",
                headers=request_headers,
                content=content,
                json=json,
            )

    except httpx.TimeoutException:
        raise StorageError(
            503,
            "Image storage timed out. Please try again shortly.",
        ) from None

    except httpx.RequestError:
        raise StorageError(
            503,
            "Cannot reach image storage.",
        ) from None

    if not 200 <= response.status_code < 300:
        # Do not expose provider responses or credentials to clients.
        raise StorageError(
            502,
            f"Image storage request failed "
            f"(HTTP {response.status_code}).",
        )

    return response


def upload_image(path, image_bytes, content_type):
    """Internal helper; caller must validate image contents and ownership."""
    encoded_path = _object_path(path)

    if content_type not in ALLOWED_CONTENT_TYPES:
        raise StorageError(400, "Use a JPEG, PNG, or WebP image.")

    if not isinstance(image_bytes, bytes) or not image_bytes:
        raise StorageError(400, "The image is empty or invalid.")

    if len(image_bytes) > MAX_IMAGE_BYTES:
        raise StorageError(413, "The image must be 2 MiB or smaller.")

    _, _, bucket = _configuration()

    _request(
        "POST",
        f"/object/{quote(bucket, safe='')}/{encoded_path}",
        content=image_bytes,
        headers={
            "Content-Type": content_type,
            "x-upsert": "false",
            "Cache-Control": "max-age=3600",
        },
    )


def create_signed_url(path, expires_in=900):
    """Internal helper; caller must authorize access before signing."""
    encoded_path = _object_path(path)

    if (
        isinstance(expires_in, bool)
        or not isinstance(expires_in, int)
        or not 1 <= expires_in <= 3600
    ):
        raise StorageError(400, "Invalid image link lifetime.")

    root, _, bucket = _configuration()

    response = _request(
        "POST",
        f"/object/sign/{quote(bucket, safe='')}/{encoded_path}",
        json={"expiresIn": expires_in},
    )

    try:
        payload = response.json()
        signed_path = payload.get("signedURL")
    except (ValueError, AttributeError):
        raise StorageError(
            502, "Image storage returned an invalid link."
        ) from None

    if not isinstance(signed_path, str):
        raise StorageError(502, "Image storage returned no link.")

    if signed_path.startswith("/object/sign/"):
        return f"{root}/storage/v1{signed_path}"

    if signed_path.startswith("/storage/v1/object/sign/"):
        return f"{root}{signed_path}"

    # Support absolute URLs only from our configured storage origin.
    parsed = urlsplit(signed_path)
    expected = urlsplit(root)

    if (
        parsed.scheme == expected.scheme
        and parsed.netloc == expected.netloc
        and parsed.path.startswith("/storage/v1/object/sign/")
    ):
        return signed_path

    raise StorageError(502, "Image storage returned an invalid link.")


def delete_image(path):
    """Internal helper; caller must authorize deletion."""
    _object_path(path)
    _, _, bucket = _configuration()

    _request(
        "DELETE",
        f"/object/{quote(bucket, safe='')}",
        json={"prefixes": [path]},
    )