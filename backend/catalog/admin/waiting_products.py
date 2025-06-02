from fastapi import APIRouter, Depends, HTTPException, Path, status
import db
from auth.depends import get_current_user

router = APIRouter(
    prefix="/products/waiting",
    tags=["Admin"]
)

def check_admin_role(current_user: dict):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")

@router.get("/", status_code=status.HTTP_200_OK)
async def get_waiting_products(current_user: dict = Depends(get_current_user)):
    """Get all products with 'waiting' status"""
    check_admin_role(current_user)

    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    async with db.pool.acquire() as conn:
        products = await conn.fetch(
            '''SELECT p.*, s.user_id as seller_user_id, u.username as seller_username 
            FROM "Products" p
            JOIN "Sellers" s ON p.seller_id = s.seller_id
            JOIN "Users" u ON s.user_id = u.user_id
            WHERE p.status = $1
            ORDER BY p.product_id''',
            "waiting"
        )

        return [dict(product) for product in products]

@router.put("/approve/{product_id}", status_code=status.HTTP_200_OK)
async def approve_product(
    product_id: int = Path(..., description="ID продукта для одобрения"),
    current_user: dict = Depends(get_current_user)
):
    """Approve a product by changing its status from 'waiting' to 'available'"""
    check_admin_role(current_user)

    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    async with db.pool.acquire() as conn:
        product = await conn.fetchrow(
            'SELECT product_id, status FROM "Products" WHERE product_id = $1',
            product_id
        )
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")

        if product["status"] != "waiting":
            raise HTTPException(
                status_code=400, 
                detail=f"Product {product_id} is not in waiting status"
            )

        await conn.execute(
            'UPDATE "Products" SET status = $1 WHERE product_id = $2',
            "available", product_id
        )

    return {"detail": f"Product {product_id} approved successfully."}

@router.delete("/{product_id}", status_code=status.HTTP_200_OK)
async def reject_product(
    product_id: int = Path(..., description="ID продукта для отклонения"),
    current_user: dict = Depends(get_current_user)
):
    """Reject a product by changing its status from 'waiting' to 'rejected'"""
    check_admin_role(current_user)

    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    async with db.pool.acquire() as conn:
        product = await conn.fetchrow(
            'SELECT product_id, status FROM "Products" WHERE product_id = $1',
            product_id
        )
        if not product:
            raise HTTPException(status_code=404, detail="Product not found")

        if product["status"] != "waiting":
            raise HTTPException(
                status_code=400,
                detail=f"Product {product_id} is not in waiting status"
            )

        await conn.execute(
            'UPDATE "Products" SET status = $1 WHERE product_id = $2',
            "rejected", product_id
        )

    return {"detail": f"Product {product_id} rejected successfully."}
