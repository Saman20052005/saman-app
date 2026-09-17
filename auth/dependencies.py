from fastapi import Header, HTTPException


async def get_token_header(authorization: str | None = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        print(f"MISSING AUTH HEADER: {authorization}")
        raise HTTPException(status_code=401, detail="Token missing or invalid format")
    return authorization.split(" ", 1)[1]
