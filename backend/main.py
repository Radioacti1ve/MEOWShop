from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
import logging
from auth import router as auth_router, admin_router
from catalog.basic.products import router as products_router
from catalog.basic.product import router as product_router
from catalog.basic.sellers_categories import router as sellers_categories_router
from catalog.basic import comments
from catalog.basic import comments_by_user 
from catalog.search.endpoints import router as search_router
from catalog.admin.products_status import router as products_status_router
from catalog.admin.ban_user import router as ban_user_router
from catalog.admin.waiting_products import router as waiting_products_router
from debug.endpoints import router as debug_router
from catalog.basic_authorization.get_orders import router as orders_router
from catalog.basic_authorization.profile import router as profile_router
from catalog.basic_authorization.write_comments import router as write_comments_router
from catalog.client.cart import router as cart_router
from catalog.client.gambling import router as gambling_router
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
    version="0.1",
    openapi_tags=[
        {
            "name": "Authentication",
            "description": "Операции авторизации и аутентификации"
        }
    ],
    swagger_ui_init_oauth={
        "usePkceWithAuthorizationCodeGrant": True,
        "useBasicAuthenticationWithAccessCodeGrant": True
    }
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
app.include_router(product_router, prefix="/catalog", tags=["Products"])
app.include_router(products_router, prefix="/catalog", tags=["Products"])
app.include_router(sellers_categories_router)

# Комментарии
app.include_router(comments.router, prefix="/catalog", tags=["Comments"])
app.include_router(comments_by_user.router, prefix="/catalog/users", tags=["Comments"])
app.include_router(write_comments_router, prefix="/catalog", tags=["Comments"])

# Поиск и профиль
app.include_router(search_router, prefix="/catalog/search", tags=["Search"])
app.include_router(profile_router, prefix="/users", tags=["Profile"])

# Заказы
app.include_router(orders_router, prefix="/users", tags=["Orders"])

# Админ панель
app.include_router(products_status_router, prefix="/admin", tags=["Admin"])
app.include_router(ban_user_router, prefix="/admin", tags=["Admin"])
app.include_router(waiting_products_router, prefix="/admin", tags=["Admin"])
app.include_router(debug_router, prefix="/debug", tags=["Debug"])

# Корзина и покупки
app.include_router(cart_router, prefix="/catalog", tags=["Cart"])
app.include_router(gambling_router, prefix="/catalog/gambling", tags=["Purchase"])
