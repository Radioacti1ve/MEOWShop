from typing import Optional, List, Dict, Any
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, constr, confloat, conint
import db
from auth.depends import get_current_user

router = APIRouter(
    prefix="/seller",
    tags=["Seller"]
)


class ProductCreate(BaseModel):
    product_name: constr(min_length=1, max_length=255)
    description: constr(min_length=1)
    category: constr(min_length=1, max_length=255)
    price: confloat(gt=0)
    in_stock: conint(ge=0)

class ProductUpdate(BaseModel):
    product_name: Optional[constr(min_length=1, max_length=255)] = None
    description: Optional[constr(min_length=1)] = None
    category: Optional[constr(min_length=1, max_length=255)] = None
    price: Optional[confloat(gt=0)] = None
    in_stock: Optional[conint(ge=0)] = None

class ProductStatusUpdate(BaseModel):
    status: constr(regex='^(available|out_of_stock|disabled)$')

def check_seller_role(current_user: dict):
    if current_user.get("role") != "seller":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Only sellers can access this endpoint"
        )

async def get_seller_id(conn, user_id: int) -> int:
    seller = await conn.fetchrow(
        'SELECT seller_id FROM "Sellers" WHERE user_id = $1',
        user_id
    )
    if not seller:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Seller profile not found"
        )
    return seller["seller_id"]

@router.post("/products", status_code=status.HTTP_201_CREATED)
async def create_product(
    product: ProductCreate,
    current_user: dict = Depends(get_current_user)
):

    check_seller_role(current_user)
    
    if db.pool is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database connection not initialized"
        )

    async with db.pool.acquire() as conn:
        seller_id = await get_seller_id(conn, current_user["user_id"])
        
        new_product = await conn.fetchrow(
            '''INSERT INTO "Products" 
               (seller_id, product_name, description, category, price, in_stock, status)
               VALUES ($1, $2, $3, $4, $5, $6, $7)
               RETURNING *''',
            seller_id,
            product.product_name,
            product.description,
            product.category,
            product.price,
            product.in_stock,
            "waiting"
        )
        
        return dict(new_product)

@router.get("/products", response_model=List[Dict[str, Any]])
async def get_seller_products(
    current_user: dict = Depends(get_current_user)
):

    check_seller_role(current_user)
    
    if db.pool is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database connection not initialized"
        )

    async with db.pool.acquire() as conn:
        seller_id = await get_seller_id(conn, current_user["user_id"])
        
        products = await conn.fetch(
            '''SELECT p.*, 
                      COALESCE(array_agg(pi.image_filename) FILTER (WHERE pi.image_filename IS NOT NULL), '{}') as images
               FROM "Products" p
               LEFT JOIN "Product_images" pi ON p.product_id = pi.product_id
               WHERE p.seller_id = $1
               GROUP BY p.product_id
               ORDER BY p.product_id''',
            seller_id
        )
        
        return [dict(product) for product in products]

@router.patch("/products/{product_id}")
async def update_product(
    product_id: int,
    update_data: ProductUpdate,
    current_user: dict = Depends(get_current_user)
):

    check_seller_role(current_user)
    
    if db.pool is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database connection not initialized"
        )

    async with db.pool.acquire() as conn:
        seller_id = await get_seller_id(conn, current_user["user_id"])
        

        product = await conn.fetchrow(
            'SELECT * FROM "Products" WHERE product_id = $1 AND seller_id = $2',
            product_id, seller_id
        )
        if not product:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Product not found or doesn't belong to you"
            )


        if product["status"] == "waiting":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot update product with 'waiting' status"
            )


        update_fields = []
        values = []
        if update_data.product_name is not None:
            update_fields.append("product_name = $" + str(len(values) + 3))
            values.append(update_data.product_name)
        if update_data.description is not None:
            update_fields.append("description = $" + str(len(values) + 3))
            values.append(update_data.description)
        if update_data.category is not None:
            update_fields.append("category = $" + str(len(values) + 3))
            values.append(update_data.category)
        if update_data.price is not None:
            update_fields.append("price = $" + str(len(values) + 3))
            values.append(update_data.price)
        if update_data.in_stock is not None:
            update_fields.append("in_stock = $" + str(len(values) + 3))
            values.append(update_data.in_stock)

        if not update_fields:
            return dict(product)

        query = f'''
            UPDATE "Products"
            SET {", ".join(update_fields)}
            WHERE product_id = $1 AND seller_id = $2
            RETURNING *
        '''
        
        updated_product = await conn.fetchrow(
            query,
            product_id,
            seller_id,
            *values
        )
        
        return dict(updated_product)

@router.patch("/products/{product_id}/status")
async def update_product_status(
    product_id: int,
    status_update: ProductStatusUpdate,
    current_user: dict = Depends(get_current_user)
):

    check_seller_role(current_user)
    
    if db.pool is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database connection not initialized"
        )

    async with db.pool.acquire() as conn:
        seller_id = await get_seller_id(conn, current_user["user_id"])
        
        # Проверяем существование товара и его текущий статус
        product = await conn.fetchrow(
            'SELECT * FROM "Products" WHERE product_id = $1 AND seller_id = $2',
            product_id, seller_id
        )
        if not product:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Product not found or doesn't belong to you"
            )
        
        if product["status"] == "waiting":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot update status of products in waiting state"
            )
        
        updated_product = await conn.fetchrow(
            '''UPDATE "Products"
               SET status = $3
               WHERE product_id = $1 AND seller_id = $2
               RETURNING *''',
            product_id,
            seller_id,
            status_update.status
        )
        
        return dict(updated_product)

@router.delete("/products/{product_id}")
async def delete_product(
    product_id: int,
    current_user: dict = Depends(get_current_user)
):
    """Удаление товара"""
    check_seller_role(current_user)
    
    if db.pool is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database connection not initialized"
        )

    async with db.pool.acquire() as conn:
        seller_id = await get_seller_id(conn, current_user["user_id"])
        
        deleted = await conn.fetchrow(
            'DELETE FROM "Products" WHERE product_id = $1 AND seller_id = $2 RETURNING product_id',
            product_id,
            seller_id
        )
        
        if not deleted:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Product not found or doesn't belong to you"
            )
        
        return {"status": "success", "detail": "Product deleted successfully"}
