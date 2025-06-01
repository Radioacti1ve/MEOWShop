from fastapi import APIRouter, Depends, HTTPException, Path, status
import db
from auth.depends import get_current_user

router = APIRouter(
    prefix="/admin/products",
    tags=["Admin"]
)

def check_admin_role(current_user: dict):
    if current_user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Not enough permissions")

@router.put("/disable/{product_id}", status_code=status.HTTP_200_OK)
async def disable_product(
    product_id: int = Path(..., description="ID продукта для деактивации"),
    current_user: dict = Depends(get_current_user)
):
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

        if product["status"] == "disabled":
            return {"detail": f"Product {product_id} is already disabled"}

        await conn.execute(
            'UPDATE "Products" SET status = $1 WHERE product_id = $2',
            "disabled", product_id
        )

    return {"detail": f"Product {product_id} disabled successfully."}

@router.put("/enable/{product_id}", status_code=status.HTTP_200_OK)
async def enable_product(
    product_id: int = Path(..., description="ID продукта для включения"),
    current_user: dict = Depends(get_current_user)
):
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

        if product["status"] == "available":
            return {"detail": f"Product {product_id} is already available"}

        await conn.execute(
            'UPDATE "Products" SET status = $1 WHERE product_id = $2',
            "available", product_id
        )

    return {"detail": f"Product {product_id} enabled successfully."}

@router.put("/disable_all/{seller_id}", status_code=status.HTTP_200_OK)
async def disable_all_products(
    seller_id: int = Path(..., description="ID продавца, у которого нужно отключить все товары"),
    current_user: dict = Depends(get_current_user)
):
    check_admin_role(current_user)

    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    async with db.pool.acquire() as conn:
        seller = await conn.fetchrow(
            'SELECT seller_id FROM "Sellers" WHERE seller_id = $1',
            seller_id
        )
        if not seller:
            raise HTTPException(status_code=404, detail="Seller not found")

        await conn.execute(
            'UPDATE "Products" SET status = $1 WHERE seller_id = $2',
            "disabled", seller_id
        )

    return {"detail": f"All products for seller {seller_id} disabled successfully."}

@router.put("/enable_all/{seller_id}", status_code=status.HTTP_200_OK)
async def enable_all_products(
    seller_id: int = Path(..., description="ID продавца, у которого нужно включить все товары"),
    current_user: dict = Depends(get_current_user)
):
    check_admin_role(current_user)

    if db.pool is None:
        raise HTTPException(status_code=500, detail="DB pool not initialized")

    async with db.pool.acquire() as conn:
        seller = await conn.fetchrow(
            'SELECT seller_id FROM "Sellers" WHERE seller_id = $1',
            seller_id
        )
        if not seller:
            raise HTTPException(status_code=404, detail="Seller not found")

        await conn.execute(
            'UPDATE "Products" SET status = $1 WHERE seller_id = $2',
            "available", seller_id
        )

    return {"detail": f"All products for seller {seller_id} enabled successfully."}
