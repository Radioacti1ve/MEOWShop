from fastapi import FastAPI, HTTPException, status, Request, Depends, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, HTTPBearer
from pydantic import BaseModel
from catalog import seller
from typing import Optional, List
import security, db

security_scheme = HTTPBearer()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

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

class UserLogin(BaseModel):
    username: str
    password: str

class UserRegister(BaseModel):
    username: str
    email: str
    password: str

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

@app.get("/")
async def root():
    return {"message": "Welcome to MEOWShop API V 0.1632.325.29GG3682.326230000VS029949.0000000001"}

@app.post("/login")
async def login(user: UserLogin):
    db_user = db.get_user_by_username(user.username)
    if not db_user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password"
        )
    if not security.verify_password(user.password, db_user["password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password"
        )
    
    token = security.create_access_token({"sub": user.username})
    return {"access_token": token, "token_type": "bearer"}

@app.post("/register")
async def register(user: UserRegister):
    existing_user = db.get_user_by_username(user.username)
    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Username already registered"
        )
    
    hashed_password = security.get_password_hash(user.password)
    new_user = db.create_user(user.username, user.email, hashed_password)
    return {"message": "User created successfully", "user_id": new_user["user_id"]}

@app.get("/protected", dependencies=[Depends(security_scheme)])
async def protected_route(token: str = Depends(oauth2_scheme)):
    payload = security.verify_token(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"}
        )
    return {"message": "This is a protected route", "user": payload["sub"]}

@app.put("/seller/profile", dependencies=[Depends(security_scheme)])
async def update_profile(user_id: int, data: SellerProfileUpdate):
    result = seller.update_seller_profile(user_id, data.description)
    if not result:
        raise HTTPException(status_code=404, detail="Seller not found")
    return result

@app.post("/seller/product", dependencies=[Depends(security_scheme)])
async def add_product(seller_id: int, data: ProductCreate):
    product = seller.add_product(seller_id, data.product_name, data.description, data.category, data.price, data.in_stock)
    return product

@app.put("/seller/product", dependencies=[Depends(security_scheme)])
async def update_product(seller_id: int, data: ProductUpdate):
    updated = seller.update_product(seller_id, data.product_id, data.product_name, data.description, data.category, data.price, data.in_stock)
    if not updated:
        raise HTTPException(status_code=404, detail="Product not found or not yours")
    return updated

@app.delete("/seller/product", dependencies=[Depends(security_scheme)])
async def delete_product(seller_id: int, data: ProductDelete):
    deleted = seller.delete_product(seller_id, data.product_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="Product not found or not yours")
    return {"message": "Product deleted"}

@app.get("/seller/orders", dependencies=[Depends(security_scheme)])
async def get_orders(seller_id: int):
    orders = seller.get_orders_with_seller_products(seller_id)
    return orders

@app.put("/seller/product/status", dependencies=[Depends(security_scheme)])
async def set_status(seller_id: int, data: ProductStatusUpdate):
    updated = seller.set_product_status(seller_id, data.product_id, data.status)
    if not updated:
        raise HTTPException(status_code=404, detail="Product not found or not yours")
    return updated

@app.get("/seller/comments", dependencies=[Depends(security_scheme)])
async def get_comments(seller_id: int):
    comments = seller.get_comments_for_seller_products(seller_id)
    return comments
# eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJNQU1VVCBSQUhBTCIsImV4cCI6MTc0ODU0NzI2Nn0.EygPdB_bdRcuUW2XkBCBEJj-pC6a9ps3lYMG2rtoznA