from fastapi import APIRouter, Query, HTTPException
from typing import Optional
import psycopg2.extras
import db

router = APIRouter()


@router.get("/products/{product_id}/comments")
def get_comments_for_product(
    product_id: int,
    sort_by: Optional[str] = Query("created_at", enum=["created_at", "rating"]),
    order: Optional[str] = Query("desc", enum=["asc", "desc"])
):
    try:
        conn = db.get_db_connection()
        cur = conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor)

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
            WHERE c.product_id = %s
            ORDER BY {sort_by} {order.upper()}
        """
        cur.execute(query, (product_id,))
        comments = cur.fetchall()
        return comments

    except Exception as e:
        print("ERROR:", e)
        raise HTTPException(status_code=500, detail="Internal Server Error")

    finally:
        if conn:
            conn.close()
