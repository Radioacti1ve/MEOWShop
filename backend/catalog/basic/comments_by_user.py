from fastapi import APIRouter, Query, HTTPException
from typing import Optional
import psycopg2.extras
import db

router = APIRouter(prefix="/api/users", tags=["comments_by_user"])

@router.get("/{user_id}/comments")
def get_comments_by_user(
    user_id: int,
    sort_by: Optional[str] = Query("created_at", regex="^(created_at|rating)$"),
    order: Optional[str] = Query("desc", regex="^(asc|desc)$")
):
    conn = db.get_db_connection()
    try:
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

        cur.execute(
            'SELECT user_id, email, username FROM "Users" WHERE user_id = %s',
            (user_id,)
        )
        user = cur.fetchone()
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
            WHERE u.user_id = %s
            ORDER BY {sort_by} {order.upper()}
        '''
        cur.execute(query, (user_id,))
        comments = cur.fetchall()

        return comments
    finally:
        conn.close()
