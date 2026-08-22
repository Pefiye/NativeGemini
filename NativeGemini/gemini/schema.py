from __future__ import annotations


def response_schema():
    from google.genai import types

    return types.Schema(
        type=types.Type.OBJECT,
        properties={
            "emotion": types.Schema(
                type=types.Type.STRING,
                description=(
                    "One word describing the emotional tone of your answer. "
                    "Pick the closest match from the available set provided in context; "
                    "if genuinely nothing fits, use 'neutral'."
                ),
            ),
            "answer": types.Schema(
                type=types.Type.STRING,
                description=(
                    "The actual answer to the user, formatted in Markdown "
                    "(##/### headers, - bullet lists, **bold**, `code`)."
                ),
            ),
        },
        required=["emotion", "answer"],
    )
