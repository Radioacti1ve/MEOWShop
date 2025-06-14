from fastapi import APIRouter, Depends, HTTPException, Path, status
import db
from auth.depends import get_current_user, require_role

router = APIRouter(
    tags=["Admin"]
)

@router.put("/ban/{user_id}")
async def ban_user(
    user_id: int = Path(..., description="ID пользователя для бана"),
    current_user: dict = Depends(require_role(["admin"]))
):
    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    if current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")

    if current_user["user_id"] == user_id:
        raise HTTPException(status_code=400, detail="You cannot ban yourself")

    async with db.pool.acquire() as conn:
        target_user = await conn.fetchrow(
            'SELECT user_id, role, username, is_active FROM "Users" WHERE user_id = $1',
            user_id
        )
        if not target_user:
            raise HTTPException(status_code=404, detail="User not found")

        if target_user["role"] == "admin":
            raise HTTPException(status_code=403, detail="Cannot ban another admin")

        if target_user["is_active"] is False:
            return {"message": "User is already banned"}

        await conn.execute(
            'UPDATE "Users" SET is_active = FALSE WHERE user_id = $1',
            user_id
        )
        
        cache_key = f"user:{target_user['username']}"
        await db.redis_client.delete(cache_key)

    return {"message": f"User {user_id} has been banned successfully"}


@router.put("/unban/{user_id}")
async def unban_user(
    user_id: int = Path(..., description="ID пользователя для разбанивания"),
    current_user: dict = Depends(require_role(["admin"]))
):
    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    if current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")

    async with db.pool.acquire() as conn:
        target_user = await conn.fetchrow(
            'SELECT user_id, role, username, is_active FROM "Users" WHERE user_id = $1',
            user_id
        )
        if not target_user:
            raise HTTPException(status_code=404, detail="User not found")

        if target_user["is_active"] is True:
            return {"message": "User is not banned"}

        await conn.execute(
            'UPDATE "Users" SET is_active = TRUE WHERE user_id = $1',
            user_id
        )
        
        cache_key = f"user:{target_user['username']}"
        await db.redis_client.delete(cache_key)

    return {"message": f"User {user_id} has been unbanned successfully"}
