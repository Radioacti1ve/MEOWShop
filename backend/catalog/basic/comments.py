from fastapi import APIRouter, Query, HTTPException
from typing import Optional
import db  

router = APIRouter()

@router.get("/products/{product_id}/comments")
async def get_comments_for_product(
    product_id: int,
    sort_by: Optional[str] = Query("created_at", enum=["created_at", "rating"]),
    order: Optional[str] = Query("desc", enum=["asc", "desc"])
):
    if sort_by not in ["created_at", "rating"]:
        raise HTTPException(status_code=400, detail="Invalid sort_by parameter")
    if order.lower() not in ["asc", "desc"]:
        raise HTTPException(status_code=400, detail="Invalid order parameter")

    query = f"""
        SELECT
            c.comment_id,
            c.user_id,
            u.username,
            c.text,
            c.rating,
            c.created_at
        FROM "Comments" c
        JOIN "Users" u ON c.user_id = u.user_id
        WHERE c.product_id = $1
        ORDER BY {sort_by} {order.upper()}
    """

    try:
        async with db.pool.acquire() as conn:
            comments = await conn.fetch(query, product_id)
        return [dict(comment) for comment in comments]

    except Exception as e:
        print("ERROR:", e)
        raise HTTPException(status_code=500, detail="Internal Server Error")
