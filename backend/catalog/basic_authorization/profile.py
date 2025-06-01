from fastapi import APIRouter, Depends, HTTPException, Body
from typing import Annotated
from authorization import db
from authorization.depends import get_current_user

router = APIRouter()

@router.put("/profile/update")
async def update_profile(
    current_user: Annotated[dict, Depends(get_current_user)],
    new_username: str = Body(..., embed=True),
    new_email: str = Body(..., embed=True),
    new_description: str | None = Body(None, embed=True)  
):
    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    user_id = current_user.get("user_id")
    role = current_user.get("role")

    async with db.pool.acquire() as conn:
        email_check = await conn.fetchrow(
            'SELECT user_id FROM "Users" WHERE email = $1 AND user_id != $2',
            new_email, user_id
        )
        if email_check:
            raise HTTPException(status_code=400, detail="Email already in use")

        old_data = await conn.fetchrow(
            '''
            SELECT u.username, u.email, s.description
            FROM "Users" u
            LEFT JOIN "Sellers" s ON u.user_id = s.user_id
            WHERE u.user_id = $1
            ''',
            user_id
        )

        await conn.execute(
            '''
            INSERT INTO "User_profile_history" (user_id, old_username, old_email, old_description)
            VALUES ($1, $2, $3, $4)
            ''',
            user_id,
            old_data["username"],
            old_data["email"],
            old_data["description"] if "description" in old_data else None
        )

        await conn.execute(
            'UPDATE "Users" SET username = $1, email = $2 WHERE user_id = $3',
            new_username, new_email, user_id
        )

        if role == "seller" and new_description is not None:
            seller_exists = await conn.fetchrow(
                'SELECT seller_id FROM "Sellers" WHERE user_id = $1',
                user_id
            )
            if seller_exists:
                await conn.execute(
                    'UPDATE "Sellers" SET description = $1 WHERE user_id = $2',
                    new_description, user_id
                )
            else:
                await conn.execute(
                    'INSERT INTO "Sellers" (user_id, description) VALUES ($1, $2)',
                    user_id, new_description
                )

    return {"message": "Profile updated successfully"}
