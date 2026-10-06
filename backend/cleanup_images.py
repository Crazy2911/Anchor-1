import argparse

from database import connect
from storage_service import StorageError, delete_image


def find_candidates():
    with connect() as connection:
        return connection.execute(
            """
            SELECT i.id, i.object_path
            FROM community_images AS i
            WHERE i.created_at < NOW() - INTERVAL '24 hours'
              AND NOT EXISTS (
                  SELECT 1
                  FROM posts AS p
                  WHERE p.image_id = i.id
              )
            ORDER BY i.created_at
            LIMIT 100
            """
        ).fetchall()


def claim_image(image_id):
    with connect() as connection:
        # The attachment endpoint also locks this image row.
        # Skip images currently being changed by another request.
        image = connection.execute(
            """
            SELECT id, object_path
            FROM community_images
            WHERE id = %s
              AND created_at < NOW() - INTERVAL '24 hours'
            FOR UPDATE SKIP LOCKED
            """,
            (image_id,),
        ).fetchone()

        if image is None:
            return None

        # Recheck after acquiring the lock, using a fresh statement.
        linked = connection.execute(
            """
            SELECT id
            FROM posts
            WHERE image_id = %s
            LIMIT 1
            """,
            (image_id,),
        ).fetchone()

        if linked is not None:
            return None

        connection.execute(
            """
            UPDATE community_images
            SET status = 'deleting'
            WHERE id = %s
            """,
            (image_id,),
        )

    # Committed status prevents new attachments while storage is deleted.
    return image["object_path"]


def finish_cleanup(image_id):
    with connect() as connection:
        connection.execute(
            """
            DELETE FROM community_images AS i
            WHERE i.id = %s
              AND i.status = 'deleting'
              AND NOT EXISTS (
                  SELECT 1
                  FROM posts AS p
                  WHERE p.image_id = i.id
              )
            """,
            (image_id,),
        )


def main():
    parser = argparse.ArgumentParser(
        description="Remove unused community images older than 24 hours."
    )
    parser.add_argument(
        "--apply",
        action="store_true",
        help="Delete eligible files and database records.",
    )
    args = parser.parse_args()

    candidates = find_candidates()
    print(f"Found {len(candidates)} candidates (maximum 100 per run).")

    if not args.apply:
        for image in candidates:
            print("Candidate:", image["id"])

        print("Preview only. No files or records were changed.")
        print("Run with --apply to perform cleanup.")
        return

    deleted = 0
    failed = 0

    for image in candidates:
        try:
            path = claim_image(image["id"])

            if path is None:
                print("Skipped: image is linked, busy, or already removed.")
                continue

            delete_image(path)
            finish_cleanup(image["id"])
            deleted += 1
            print("Removed:", image["id"])

        except StorageError as error:
            failed += 1
            print("Storage cleanup failed:", error.message)

        except Exception as error:
            failed += 1
            # Avoid printing connection strings or provider credentials.
            print("Cleanup failed:", type(error).__name__)

    print(f"Finished: {deleted} removed, {failed} failed.")
    print("Failed records remain available for a later cleanup attempt.")


if __name__ == "__main__":
    main()