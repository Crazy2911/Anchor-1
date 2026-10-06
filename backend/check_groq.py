import os

from groq import Groq, APIStatusError, APIConnectionError


def main():
    api_key = os.environ.get("GROQ_API_KEY", "").strip()
    model = os.environ.get("GROQ_MODEL", "").strip()

    if not api_key or not model:
        print("Set GROQ_API_KEY and GROQ_MODEL in this terminal first.")
        return

    # One diagnostic attempt; no automatic retries.
    client = Groq(
        api_key=api_key,
        timeout=20.0,
        max_retries=0,
    )

    try:
        response = client.chat.completions.create(
            model=model,
            messages=[
                {
                    "role": "user",
                    "content": "Reply with: Connection successful",
                }
            ],
            max_tokens=100,
        )

        print(response.choices[0].message.content)

    except APIStatusError as error:
        print(f"HTTP status: {error.status_code}")

        details = error.response.text.replace(api_key, "[REDACTED]")
        print(details[:2000])

    except APIConnectionError:
        print("Connection failed before an API response was received.")

    finally:
        client.close()


if __name__ == "__main__":
    main()