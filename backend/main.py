from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import logging
from auth import router as auth_router, admin_router
from catalog.basic import products 
from catalog.basic.product import router as product_router 
from catalog.basic.sellers_categories import router as sellers_categories_router
from catalog.basic import comments
from catalog.basic import comments_by_user 
from catalog.basic_authorization import write_comments
from catalog.search.endpoints import router as search_router
from catalog.basic.admin_routes import router as admin_router
from debug.endpoints import router as debug_router
from elastic.client import get_elasticsearch_client
from elastic.mappings import create_product_index, PRODUCT_INDEX_NAME
import db

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="MEOWShop API",
    description="API для MEOWShop с аутентификацией",
    version="0.1"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
async def startup_event():
    """Initialize application resources on startup"""
    logger.info("Starting application initialization...")
    
    logger.info("Initializing database pool...")
    try:
        await db.init_db_pool()
        logger.info("Database pool initialized successfully")
    except Exception as e:
        logger.error(f"Failed to initialize database pool: {e}")
        raise
    
    logger.info("Initializing Elasticsearch client...")
    es_client = get_elasticsearch_client()
    await es_client.initialize()
    logger.info("Elasticsearch client initialized")
    
    logger.info("Creating/updating Elasticsearch index mapping...")
    await create_product_index(es_client.get_client())
    logger.info("Index mapping created/updated successfully")
    
    logger.info("Starting product synchronization with Elasticsearch...")
    from elastic.sync import sync_products_to_elasticsearch
    await sync_products_to_elasticsearch()
    logger.info("Successfully synchronized products with Elasticsearch")

@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup application resources on shutdown"""
    logger.info("Starting application shutdown...")
    
    logger.info("Closing database pool...")
    await db.close_db_pool()
    logger.info("Database pool closed")
    
    logger.info("Closing Elasticsearch connection...")
    es_client = get_elasticsearch_client()
    await es_client.close()
    logger.info("Elasticsearch connection closed")

@app.get("/")
async def root():
    return {"message": "Welcome to MEOWShop API V 0.1"}

# Роутеры
app.include_router(auth_router)
app.include_router(admin_router)
app.include_router(products.router, prefix="/catalog", tags=["Products"])
app.include_router(product_router, prefix="/catalog")
app.include_router(sellers_categories_router)
app.include_router(comments.router, prefix="/catalog", tags=["comments"])
app.include_router(comments_by_user.router, prefix="/catalog/users")
app.include_router(write_comments.router)
app.include_router(search_router)
app.include_router(admin_router)
app.include_router(debug_router)
