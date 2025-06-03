from typing import Optional, List, Dict, Any
import db
from fastapi import APIRouter, Depends, HTTPException, status, File, UploadFile
from auth.depends import get_current_user
from .seller import check_seller_role, get_seller_id 

import csv
import openpyxl
import json
import xml.etree.ElementTree as ET
from io import StringIO, BytesIO

import logging


logger = logging.getLogger(__name__)
router = APIRouter(tags=["ETL"])

router = APIRouter(
    prefix="/etl",
    tags=["ETL"]
)


def process_csv_file(content: bytes, required_fields: set) -> List[Dict[str, Any]]:

    products = []
    decoded = content.decode('utf-8')
    sample = decoded[:2048]
    sniffer = csv.Sniffer()
    try:
        dialect = sniffer.sniff(sample, delimiters=",;\t|")
        delimiter = dialect.delimiter
    except Exception:
        delimiter = ',' 
    reader = csv.DictReader(StringIO(decoded), delimiter=delimiter)
    for row in reader:

        product = {field: row.get(field) for field in required_fields}

        try:
            product["price"] = float(product["price"])
            product["in_stock"] = int(product["in_stock"])
        except (ValueError, TypeError):
            logger.warning(f"Invalid data in row: {row}")
            continue  
        if not all(product.get(field) for field in required_fields): 
            logger.warning(f"Missing required fields in row: {row}")
            continue  
        products.append(product)
    return products


def process_xlsx_file(content: bytes, required_fields: set) -> List[Dict[str, Any]]:

    products = []
    workbook = openpyxl.load_workbook(filename=BytesIO(content)) 
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
            logger.warning(f"Invalid data in row {row_idx}: {row_dict}")
            continue
        if not all(product.get(field) for field in required_fields): 
            logger.warning(f"Missing required fields in row {row_idx}: {row_dict}")
            continue
        products.append(product)
    return products


def process_json_file(content: bytes, required_fields: set) -> List[Dict[str, Any]]:

    products = []
    try:
        decoded = content.decode('utf-8')
        json_data = json.loads(decoded)
        

        if not isinstance(json_data, list):
            raise HTTPException(status_code=400, detail="JSON file must contain an array of products")
        
        for item in json_data:
            if not isinstance(item, dict):
                continue  
            
            
            product = {field: item.get(field) for field in required_fields}
            
            try:
                product["price"] = float(product["price"])
                product["in_stock"] = int(product["in_stock"])
            except (ValueError, TypeError):
                logger.warning(f"Invalid data in product: {item}")
                continue  
            if not all(product.get(field) for field in required_fields):
                logger.warning(f"Missing required fields in product: {item}")
                continue  
            
            products.append(product)
            
    except json.JSONDecodeError:
        raise HTTPException(status_code=400, detail="Invalid JSON format")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error processing JSON file: {str(e)}")
    return products


def process_xml_file(content: bytes, required_fields: set) -> List[Dict[str, Any]]:
    products = []
    try:
        decoded = content.decode('utf-8')
        root = ET.fromstring(decoded)
        
        for product_elem in root.findall('.//product'):
            product = {}
            
   
            for field in required_fields:

                if field in product_elem.attrib:
                    product[field] = product_elem.attrib[field]
                else:
    
                    child_elem = product_elem.find(field)
                    if child_elem is not None and child_elem.text:
                        product[field] = child_elem.text.strip()
                    else:
                        product[field] = None
            

            try:
                if product.get("price"):
                    product["price"] = float(product["price"])
                if product.get("in_stock"):
                    product["in_stock"] = int(product["in_stock"])
            except (ValueError, TypeError):
                logger.warning(f"Invalid data in product: {product}")
                continue  
            

            if not all(product.get(field) for field in required_fields):
                logger.warning(f"Missing required fields in product: {product}")
                continue 
            
            products.append(product)
            
    except ET.ParseError:
        raise HTTPException(status_code=400, detail="Invalid XML format")
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error processing XML file: {str(e)}")
    return products


@router.post("/products/upload")
async def upload_products_via_file(file: UploadFile = File(...),current_user: dict = Depends(get_current_user)):

 
    check_seller_role(current_user)
    
    if db.pool is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Database connection not initialized"
        )

    async with db.pool.acquire() as conn:
        seller_id = await get_seller_id(conn, current_user["user_id"])
        

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
    
    
    inserted = []
    async with db.pool.acquire() as conn:
        async with conn.transaction():
            for product in products:
                row = await conn.fetchrow(
                    'INSERT INTO "Products" (seller_id, product_name, description, category, price, in_stock, status) '
                    'VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *',
                    seller_id, product["product_name"], product["description"], product["category"], 
                    product["price"], product["in_stock"], "waiting"
                )
                inserted.append(dict(row))
    
    return {"inserted": inserted, "count": len(inserted)}










