from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, condecimal
from typing import Optional
from decimal import Decimal
from depends import get_current_user, require_role
from catalog.basic.product_operations import create_product, update_product, delete_product

router = APIRouter(prefix="/catalog/admin", tags=["product_admin"])

class ProductCreate(BaseModel):
    seller_id: int
    product_name: str
    description: str
    category: str
    price: condecimal(decimal_places=2, ge=Decimal('0.00'))
    in_stock: int
    status: str = "available"

class ProductUpdate(BaseModel):
    seller_id: Optional[int] = None
    product_name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[condecimal(decimal_places=2, ge=Decimal('0.00'))] = None
    in_stock: Optional[int] = None
    status: Optional[str] = None

@router.post("/products", status_code=status.HTTP_201_CREATED)
async def create_product_endpoint(
    product: ProductCreate,
    _=Depends(require_role(["admin", "seller"]))
):
    """Create a new product"""
    return await create_product(
        seller_id=product.seller_id,
        product_name=product.product_name,
        description=product.description,
        category=product.category,
        price=product.price,
        in_stock=product.in_stock,
        status=product.status
    )

@router.patch("/products/{product_id}")
async def update_product_endpoint(
    product_id: int,
    product: ProductUpdate,
    _=Depends(require_role(["admin", "seller"]))
):
    """Update a product"""
    return await update_product(
        product_id=product_id,
        seller_id=product.seller_id,
        product_name=product.product_name,
        description=product.description,
        category=product.category,
        price=product.price,
        in_stock=product.in_stock,
        status=product.status
    )

@router.delete("/products/{product_id}")
async def delete_product_endpoint(
    product_id: int,
    _=Depends(require_role(["admin", "seller"]))
):
    """Delete a product"""
    return await delete_product(product_id)
