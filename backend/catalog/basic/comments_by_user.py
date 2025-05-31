from fastapi import APIRouter, Query, HTTPException
from typing import Optional
from authorization import db

router = APIRouter(tags=["comments_by_user"])

@router.get("/{user_id}/comments")
async def get_comments_by_user(
    user_id: int,
    sort_by: Optional[str] = Query("created_at", regex="^(created_at|rating)$"),
    order: Optional[str] = Query("desc", regex="^(asc|desc)$")
):
    try:
        async with db.pool.acquire() as conn:
            user = await conn.fetchrow(
                'SELECT user_id, email, username FROM "Users" WHERE user_id = $1',
                user_id
            )
            if not user:
                raise HTTPException(status_code=404, detail="User not found")

            query = f'''
                SELECT 
                    c.comment_id,
                    c.product_id,
                    p.product_name,
                    c.text,
                    c.rating,
                    c.created_at,
                    u.username,
                    u.email
                FROM "Comments" c
                JOIN "Users" u ON c.user_id = u.user_id
                JOIN "Products" p ON c.product_id = p.product_id
                WHERE u.user_id = $1
                ORDER BY {sort_by} {order.upper()}
            '''
            comments = await conn.fetch(query, user_id)

        return comments

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
