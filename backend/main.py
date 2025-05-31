from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from authorization.auth import router as auth_router
from catalog.basic import products
from catalog.basic.product import router as product_router
from catalog.basic.sellers_categories import router as sellers_categories_router
from catalog.basic import comments
from catalog.basic import comments_by_user
from catalog.basic_authorization import write_comments
from catalog.basic_authorization import get_orders
from catalog.client import cart
from catalog.client.gambling import router as gambling_router
from authorization import db


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
    await db.init_db_pool()

@app.on_event("shutdown")
async def shutdown_event():
    if db.pool:
        await db.pool.close()

@app.get("/")
async def root():
    return {"message": "Welcome to MEOWShop API V 0.1"}

# роутеры
app.include_router(auth_router)
app.include_router(products.router, prefix="/catalog", tags=["Products"])  
app.include_router(product_router, prefix="/catalog")
app.include_router(sellers_categories_router)
app.include_router(comments.router, prefix="/catalog", tags=["comments"])
app.include_router(comments_by_user.router, prefix="/catalog/users")
app.include_router(write_comments.router)
app.include_router(get_orders.router, prefix="/catalog", tags=["orders"])
app.include_router(cart.router)
app.include_router(gambling_router)