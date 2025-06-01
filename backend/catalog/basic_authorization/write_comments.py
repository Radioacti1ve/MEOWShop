from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from typing import Annotated, Dict, Any
import datetime
import logging
import db
from auth.depends import get_current_user

logger = logging.getLogger(__name__)
router = APIRouter(tags=["Comments"])

class CommentCreate(BaseModel):
    product_id: int
    text: str = Field(..., min_length=1)
    rating: int | None = Field(None, ge=1, le=5)
    reply_to_comment_id: int | None = None

class CommentUpdate(BaseModel):
    text: str = Field(..., min_length=1)

@router.post("/comments", status_code=status.HTTP_201_CREATED)
async def create_comment(
    comment: CommentCreate,
    current_user: Annotated[dict, Depends(get_current_user)]
):
    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    async with db.pool.acquire() as conn:
        product = await conn.fetchrow('SELECT product_id FROM "Products" WHERE product_id = $1', comment.product_id)
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")

        if comment.reply_to_comment_id is not None:
            parent_comment = await conn.fetchrow('SELECT comment_id FROM "Comments" WHERE comment_id = $1', comment.reply_to_comment_id)
            if not parent_comment:
                raise HTTPException(status_code=404, detail="Parent comment not found")
        
        if current_user["role"] != "user" and comment.rating is not None:
            raise HTTPException(status_code=403, detail="Only users can rate products")

        if current_user["role"] == "user" and comment.reply_to_comment_id is None:
            existing = await conn.fetchrow('''
                SELECT 1 FROM "Comments" 
                WHERE user_id = $1 AND product_id = $2 AND reply_to_comment_id IS NULL
            ''', current_user["user_id"], comment.product_id)
            if existing:
                raise HTTPException(status_code=400, detail="You have already written a root comment on this product")

        if comment.reply_to_comment_id is not None and comment.rating is not None:
            raise HTTPException(status_code=400, detail="Replies cannot have a rating")

        created_at = datetime.datetime.utcnow()
        new_comment = await conn.fetchrow('''
            INSERT INTO "Comments" (user_id, reply_to_comment_id, product_id, text, rating, created_at)
            VALUES ($1, $2, $3, $4, $5, $6)
            RETURNING comment_id, user_id, reply_to_comment_id, product_id, text, rating, created_at
        ''', current_user["user_id"], comment.reply_to_comment_id, comment.product_id, comment.text, comment.rating, created_at)

    return {"message": "Comment created successfully", "comment": dict(new_comment)}


@router.put("/comments/{comment_id}", status_code=200)
async def update_comment(
    comment_id: int,
    data: CommentUpdate,
    current_user: Annotated[dict, Depends(get_current_user)]
):
    async with db.pool.acquire() as conn:
        comment = await conn.fetchrow('SELECT * FROM "Comments" WHERE comment_id = $1', comment_id)
        if not comment:
            raise HTTPException(status_code=404, detail="Comment not found")

        if comment["user_id"] != current_user["user_id"]:
            raise HTTPException(status_code=403, detail="You can only edit your own comments")

        updated = await conn.fetchrow('''
            UPDATE "Comments" SET text = $1 WHERE comment_id = $2
            RETURNING comment_id, text
        ''', data.text, comment_id)

    return {"message": "Comment updated", "comment": dict(updated)}


@router.delete("/comments/{comment_id}", status_code=200)
async def delete_comment(
    comment_id: int,
    current_user: Annotated[dict, Depends(get_current_user)]
):
    async with db.pool.acquire() as conn:
        comment = await conn.fetchrow('SELECT * FROM "Comments" WHERE comment_id = $1', comment_id)
        if not comment:
            raise HTTPException(status_code=404, detail="Comment not found")

        is_author = comment["user_id"] == current_user["user_id"]
        is_admin = current_user["role"] == "admin"

        if not is_author and not is_admin:
            raise HTTPException(status_code=403, detail="You can only delete your own comments")

        await conn.execute('''
            UPDATE "Comments"
            SET text = '[удалено]', rating = NULL, user_id = NULL
            WHERE comment_id = $1
        ''', comment_id)

    return {"message": "Comment deleted (soft)"}
