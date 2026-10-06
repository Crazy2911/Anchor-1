import logging
import secrets
import threading
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

from database import connect
from storage_service import (
    MAX_IMAGE_BYTES,
    StorageError,
    delete_image,
    upload_image,
)


logger = logging.getLogger(__name__)
IMAGE_SLOTS = threading.BoundedSemaphore(2)

MAX_INPUT_BYTES = 2 * 1024 * 1024
MAX_PIXELS = 16_000_000
MAX_EDGE = 1600


def prepare_image(raw):
    if not raw:
        raise StorageError(400, "Choose an image.")

    if len(raw) > MAX_INPUT_BYTES:
        raise StorageError(413, "Choose an image smaller than 2 MiB.")

    try:
        with Image.open(BytesIO(raw)) as source:
            if source.format not in {"JPEG", "PNG", "WEBP"}:
                raise StorageError(
                    400, "Only JPEG, PNG, and WebP images are supported."
                )

            if source.width * source.height > MAX_PIXELS:
                raise StorageError(
                    400, "Choose an image with at most 16 million pixels."
                )

            if getattr(source, "is_animated", False):
                raise StorageError(400, "Please choose a still image.")

            source.verify()

        with Image.open(BytesIO(raw)) as source:
            source.load()
            oriented = ImageOps.exif_transpose(source)

            try:
                oriented.thumbnail(
                    (MAX_EDGE, MAX_EDGE),
                    Image.Resampling.LANCZOS,
                )

                # Copy pixels into a fresh image without source metadata.
                with oriented.convert("RGBA") as pixels:
                    clean = Image.new("RGBA", pixels.size)
                    clean.paste(pixels)
            finally:
                oriented.close()

        try:
            for quality in (82, 70, 55):
                output = BytesIO()
                clean.save(
                    output,
                    format="WEBP",
                    quality=quality,
                    method=4,
                )
                encoded = output.getvalue()

                if len(encoded) <= MAX_IMAGE_BYTES:
                    return encoded, clean.width, clean.height

            raise StorageError(
                413, "This image is too large after compression."
            )
        finally:
            clean.close()

    except StorageError:
        raise
    except (
        UnidentifiedImageError,
        OSError,
        ValueError,
        SyntaxError,
        Image.DecompressionBombError,
    ):
        raise StorageError(
            400, "The image is damaged or unsupported."
        ) from None


def create_image(user_id, raw):
    if not IMAGE_SLOTS.acquire(blocking=False):
        raise StorageError(
            429, "Image processing is busy. Please try again shortly."
        )

    try:
        encoded, width, height = prepare_image(raw)
        image_id = secrets.token_hex(16)
        object_path = f"posts/{user_id}/{image_id}.webp"

        with connect() as connection:
            connection.execute(
                """
                INSERT INTO community_images (
                    id,
                    owner_id,
                    object_path,
                    content_type,
                    size_bytes,
                    status
                )
                VALUES (%s, %s, %s, %s, %s, 'pending')
                """,
                (
                    image_id,
                    user_id,
                    object_path,
                    "image/webp",
                    len(encoded),
                ),
            )

        try:
            upload_image(object_path, encoded, "image/webp")

            with connect() as connection:
                connection.execute(
                    """
                    UPDATE community_images
                    SET status = 'ready'
                    WHERE id = %s AND owner_id = %s
                    """,
                    (image_id, user_id),
                )

        except Exception:
            # This image has not been returned to the client or linked
            # to a post. Attempt to remove the failed upload.
            try:
                delete_image(object_path)

                with connect() as connection:
                    connection.execute(
                        """
                        DELETE FROM community_images
                        WHERE id = %s AND owner_id = %s
                        """,
                        (image_id, user_id),
                    )
            except Exception:
                # Keep the record so cleanup can find it later.
                logger.warning(
                    "Image cleanup required for image ID %s",
                    image_id,
                )
            raise

        return {
            "imageId": image_id,
            "contentType": "image/webp",
            "sizeBytes": len(encoded),
            "width": width,
            "height": height,
        }

    finally:
        IMAGE_SLOTS.release()