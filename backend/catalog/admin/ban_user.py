from fastapi import APIRouter, Depends, HTTPException, Path, status
from authorization import db
from authorization.depends import get_current_user

router = APIRouter()

@router.put("/ban/{user_id}", tags=["admin"])
async def ban_user(
    user_id: int = Path(..., description="ID пользователя для бана"),
    current_user: dict = Depends(get_current_user)
):
    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    if current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")

    if current_user["user_id"] == user_id:
        raise HTTPException(status_code=400, detail="You cannot ban yourself")

    async with db.pool.acquire() as conn:
        target_user = await conn.fetchrow(
            'SELECT user_id, role, is_active FROM "Users" WHERE user_id = $1',
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

    return {"message": f"User {user_id} has been banned successfully"}


@router.put("/unban/{user_id}", tags=["admin"])
async def unban_user(
    user_id: int = Path(..., description="ID пользователя для разбанивания"),
    current_user: dict = Depends(get_current_user)
):
    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    if current_user["role"] != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")

    async with db.pool.acquire() as conn:
        target_user = await conn.fetchrow(
            'SELECT user_id, role, is_active FROM "Users" WHERE user_id = $1',
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

    return {"message": f"User {user_id} has been unbanned successfully"}
