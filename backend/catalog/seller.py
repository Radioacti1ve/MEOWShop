import asyncpg
from typing import Optional, List, Dict, Any
from db import get_async_pool
from fastapi import APIRouter, Depends, HTTPException, status, File, UploadFile
from fastapi.security import HTTPBearer
from pydantic import BaseModel
import csv
from io import StringIO

# Создаем роутер для продавца
router = APIRouter(
    prefix="/seller",
    tags=["seller"],
    dependencies=[Depends(HTTPBearer())]
)

# Модели данных для API
class SellerProfileUpdate(BaseModel):
    description: str

class ProductCreate(BaseModel):
    product_name: str
    description: str
    category: str
    price: float
    in_stock: int

class ProductUpdate(BaseModel):
    product_id: int
    product_name: Optional[str] = None
    description: Optional[str] = None
    category: Optional[str] = None
    price: Optional[float] = None
    in_stock: Optional[int] = None

class ProductStatusUpdate(BaseModel):
    product_id: int
    status: str

class ProductDelete(BaseModel):
    product_id: int

# Эндпоинты для seller
@router.put("/profile")
async def update_profile(user_id: int, data: SellerProfileUpdate):
    result = await update_seller_profile(user_id, data.description)
    if not result:
        raise HTTPException(status_code=404, detail="Seller not found")
    return result

@router.post("/product")
async def add_product_endpoint(seller_id: int, data: ProductCreate):
    product = await add_product(seller_id, data.product_name, data.description, data.category, data.price, data.in_stock)
    return product

@router.put("/product")
async def update_product_endpoint(seller_id: int, data: ProductUpdate):
    updated = await update_product(seller_id, data.product_id, data.product_name, data.description, data.category, data.price, data.in_stock)
    if not updated:
        raise HTTPException(status_code=404, detail="Product not found or not yours")
    return updated

@router.delete("/product")
async def delete_product_endpoint(seller_id: int, data: ProductDelete):
    deleted = await delete_product(seller_id, data.product_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Product not found or not yours")
    return {"message": "Product deleted"}

@router.get("/orders")
async def get_orders_endpoint(seller_id: int):
    orders = await get_orders_with_seller_products(seller_id)
    return orders

@router.put("/product/status")
async def set_status_endpoint(seller_id: int, data: ProductStatusUpdate):
    updated = await set_product_status(seller_id, data.product_id, data.status)
    if not updated:
        raise HTTPException(status_code=404, detail="Product not found or not yours")
    return updated

@router.get("/comments")
async def get_comments_endpoint(seller_id: int):
    comments = await get_comments_for_seller_products(seller_id)
    return comments

@router.post("/products/upload")
async def upload_products_csv(seller_id: int, file: UploadFile = File(...)):
    if not file.filename.endswith('.csv'):
        raise HTTPException(status_code=400, detail="Only CSV files are supported")
    content = await file.read()
    decoded = content.decode('utf-8')
    # Автоопределение разделителя
    sample = decoded[:2048]
    sniffer = csv.Sniffer()
    try:
        dialect = sniffer.sniff(sample, delimiters=",;\t|")
        delimiter = dialect.delimiter
    except Exception:
        delimiter = ','  # fallback
    reader = csv.DictReader(StringIO(decoded), delimiter=delimiter)
    required_fields = {"product_name", "description", "category", "price", "in_stock"}
    products = []
    for row in reader:
        # Оставляем только нужные поля, игнорируем лишние
        product = {field: row.get(field) for field in required_fields}
        # Валидация и преобразование типов
        try:
            product["price"] = float(product["price"])
            product["in_stock"] = int(product["in_stock"])
        except (ValueError, TypeError):
            continue  # пропускаем некорректные строки
        if not all(product.values()):
            continue  # пропускаем строки с пустыми значениями
        products.append(product)
    if not products:
        raise HTTPException(status_code=400, detail="No valid products found in CSV")
    inserted = await bulk_insert_products(seller_id, products)
    return {"inserted": inserted, "count": len(inserted)}

# Управление профилем продавца
async def update_seller_profile(user_id: int, description: str) -> Optional[Dict[str, Any]]:
    pool = await get_async_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            'UPDATE "Sellers" SET description = $1 WHERE user_id = $2 RETURNING *', 
            description, user_id
        )
        return dict(row) if row else None

# Добавление нового товара
async def add_product(seller_id: int, product_name: str, description: str, category: str, price: float, in_stock: int) -> Dict[str, Any]:
    pool = await get_async_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            'INSERT INTO "Products" (seller_id, product_name, description, category, price, in_stock) '
            'VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
            seller_id, product_name, description, category, price, in_stock
        )
        return dict(row)

# Редактирование информации о товаре (только своих)
async def update_product(seller_id: int, product_id: int, product_name: Optional[str] = None, 
                         description: Optional[str] = None, category: Optional[str] = None, 
                         price: Optional[float] = None, in_stock: Optional[int] = None) -> Optional[Dict[str, Any]]:
    pool = await get_async_pool()
    async with pool.acquire() as conn:
        # Получаем текущие значения
        product = await conn.fetchrow(
            'SELECT * FROM "Products" WHERE product_id = $1 AND seller_id = $2', 
            product_id, seller_id
        )
        
        if not product:
            return None
            
        # Обновляем только переданные поля
        new_name = product_name if product_name is not None else product['product_name']
        new_desc = description if description is not None else product['description']
        new_cat = category if category is not None else product['category']
        new_price = price if price is not None else product['price']
        new_stock = in_stock if in_stock is not None else product['in_stock']
        
        updated = await conn.fetchrow(
            'UPDATE "Products" SET product_name=$1, description=$2, category=$3, price=$4, in_stock=$5 '
            'WHERE product_id=$6 AND seller_id=$7 RETURNING *',
            new_name, new_desc, new_cat, new_price, new_stock, product_id, seller_id
        )
        return dict(updated) if updated else None

# Удаление товара (только своих)
async def delete_product(seller_id: int, product_id: int) -> bool:
    pool = await get_async_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            'DELETE FROM "Products" WHERE product_id = $1 AND seller_id = $2 RETURNING product_id', 
            product_id, seller_id
        )
        return bool(row)

async def get_orders_with_seller_products(seller_id: int) -> List[Dict[str, Any]]:
    """
    Получить список заказов, в которых есть товары данного продавца.
    Возвращает список заказов с деталями товаров этого продавца в каждом заказе.
    """
    pool = await get_async_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch('''
            SELECT o.*, oi.product_id, oi.quantity, oi.price_ 
            FROM "Orders" o
            JOIN "Order_items" oi ON o.order_id = oi.order_id
            JOIN "Products" p ON oi.product_id = p.product_id
            WHERE p.seller_id = $1
            ORDER BY o.created_at DESC
        ''', seller_id)
        return [dict(row) for row in rows]

async def set_product_status(seller_id: int, product_id: int, status: str) -> Optional[Dict[str, Any]]:
    """
    Установить статус товара (например, 'active', 'inactive', 'archived').
    """
    pool = await get_async_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            'UPDATE "Products" SET status = $1 WHERE product_id = $2 AND seller_id = $3 RETURNING *',
            status, product_id, seller_id
        )
        return dict(row) if row else None

async def get_comments_for_seller_products(seller_id: int) -> List[Dict[str, Any]]:
    """
    Получить все комментарии ко всем товарам продавца.
    """
    pool = await get_async_pool()
    async with pool.acquire() as conn:
        rows = await conn.fetch('''
            SELECT c.*, p.product_name FROM "Comments" c
            JOIN "Products" p ON c.product_id = p.product_id
            WHERE p.seller_id = $1
            ORDER BY c.created_at DESC
        ''', seller_id)
        return [dict(row) for row in rows]

async def bulk_insert_products(seller_id: int, products: list) -> List[Dict[str, Any]]:
    """
    Массовая вставка товаров в БД. products — список dict с ключами: product_name, description, category, price, in_stock
    """
    inserted = []
    pool = await get_async_pool()
    async with pool.acquire() as conn:
        async with conn.transaction():
            for product in products:
                row = await conn.fetchrow(
                    'INSERT INTO "Products" (seller_id, product_name, description, category, price, in_stock) '
                    'VALUES ($1, $2, $3, $4, $5, $6) RETURNING *',
                    seller_id, product["product_name"], product["description"], product["category"], 
                    product["price"], product["in_stock"]
                )
                inserted.append(dict(row))
    return inserted


