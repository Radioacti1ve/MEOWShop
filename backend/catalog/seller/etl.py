import asyncpg
from typing import Optional, List, Dict, Any
from db import get_async_pool
from fastapi import APIRouter, Depends, HTTPException, status, File, UploadFile
from fastapi.security import HTTPBearer
from pydantic import BaseModel
import csv
import openpyxl
import json
import xml.etree.ElementTree as ET
from io import StringIO, BytesIO



# Создаем роутер для ETL
router = APIRouter(
    prefix="/etl",
    tags=["etl"],
    dependencies=[Depends(HTTPBearer())]
)




def process_csv_file(content: bytes, required_fields: set) -> List[Dict[str, Any]]:
    """Обработка CSV файлов"""
    products = []
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
    for row in reader:
        # Оставляем только нужные поля, игнорируем лишние
        product = {field: row.get(field) for field in required_fields}
        # Валидация и преобразование типов
        try:
            product["price"] = float(product["price"])
            product["in_stock"] = int(product["in_stock"])
        except (ValueError, TypeError):
            continue  # пропускаем некорректные строки
        if not all(product.values()): # Check if all required values are present and not empty
            continue  # пропускаем строки с пустыми значениями
        products.append(product)
    return products


def process_xlsx_file(content: bytes, required_fields: set) -> List[Dict[str, Any]]:
    """Обработка XLSX файлов"""
    products = []
    workbook = openpyxl.load_workbook(filename=BytesIO(content)) # Use BytesIO for content
    sheet = workbook.active
    header = [cell.value for cell in sheet[1]]
    for row_idx in range(2, sheet.max_row + 1):
        row_values = [cell.value for cell in sheet[row_idx]]
        row_dict = dict(zip(header, row_values))
        product = {field: row_dict.get(field) for field in required_fields}
        try:
            product["price"] = float(product["price"])
            product["in_stock"] = int(product["in_stock"])
        except (ValueError, TypeError):
            continue
        if not all(product.get(field) for field in required_fields): # More robust check for all required fields
            continue
        products.append(product)
    return products


def process_json_file(content: bytes, required_fields: set) -> List[Dict[str, Any]]:
    """Обработка JSON файлов"""
    products = []
    try:
        decoded = content.decode('utf-8')
        json_data = json.loads(decoded)
        
        # Проверяем, что JSON содержит список
        if not isinstance(json_data, list):
            raise HTTPException(status_code=400, detail="JSON file must contain an array of products")
        
        for item in json_data:
            if not isinstance(item, dict):
                continue  # пропускаем элементы, которые не являются объектами
            
            # Оставляем только нужные поля, игнорируем лишние
            product = {field: item.get(field) for field in required_fields}
            
            # Валидация и преобразование типов
            try:
                product["price"] = float(product["price"])
                product["in_stock"] = int(product["in_stock"])
            except (ValueError, TypeError):
                continue  # пропускаем некорректные строки
            
            # Проверяем, что все обязательные поля присутствуют и не пустые
            if not all(product.get(field) for field in required_fields):
                continue  # пропускаем строки с пустыми значениями
            
            products.append(product)
            
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid JSON format")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error processing JSON file: {str(e)}")
    return products


def process_xml_file(content: bytes, required_fields: set) -> List[Dict[str, Any]]:
    """Обработка XML файлов"""
    products = []
    try:
        decoded = content.decode('utf-8')
        root = ET.fromstring(decoded)
        
        # Ищем все элементы product в XML
        for product_elem in root.findall('.//product'):
            product = {}
            
            # Извлекаем данные из атрибутов или дочерних элементов
            for field in required_fields:
                # Сначала проверяем атрибуты
                if field in product_elem.attrib:
                    product[field] = product_elem.attrib[field]
                else:
                    # Затем проверяем дочерние элементы
                    child_elem = product_elem.find(field)
                    if child_elem is not None and child_elem.text:
                        product[field] = child_elem.text.strip()
                    else:
                        product[field] = None
            
            # Валидация и преобразование типов
            try:
                if product.get("price"):
                    product["price"] = float(product["price"])
                if product.get("in_stock"):
                    product["in_stock"] = int(product["in_stock"])
            except (ValueError, TypeError):
                continue  # пропускаем некорректные строки
            
            # Проверяем, что все обязательные поля присутствуют и не пустые
            if not all(product.get(field) for field in required_fields):
                continue  # пропускаем строки с пустыми значениями
            
            products.append(product)
            
    except ET.ParseError:
        raise HTTPException(status_code=400, detail="Invalid XML format")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error processing XML file: {str(e)}")
    return products


@router.post("/products/upload")
async def upload_products_via_file(seller_id: int, file: UploadFile = File(...)):
    products = []
    required_fields = {"product_name", "description", "category", "price", "in_stock"}

    content = await file.read()

    if file.filename.endswith('.csv'):
        products = process_csv_file(content, required_fields)
    elif file.filename.endswith('.xlsx'):
        products = process_xlsx_file(content, required_fields)
    elif file.filename.endswith('.json'):
        products = process_json_file(content, required_fields)
    elif file.filename.endswith('.xml'):
        products = process_xml_file(content, required_fields)
    else:
        raise HTTPException(status_code=400, detail="Only CSV, XLSX, JSON, or XML files are supported")

    if not products:
        raise HTTPException(status_code=400, detail="No valid products found in file")
    inserted = await bulk_insert_products(seller_id, products)
    return {"inserted": inserted, "count": len(inserted)}








async def bulk_insert_products(seller_id: int, products: list) -> List[Dict[str, Any]]:

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

