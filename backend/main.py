from fastapi import FastAPI, HTTPException, status, Request, Depends, Security
from fastapi.middleware.cors import CORSMiddleware
from fastapi.security import OAuth2PasswordBearer, HTTPBearer
from pydantic import BaseModel
from catalog.seller import router as seller_router
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

# Подключаем роутер для seller API
app.include_router(seller_router)

class UserLogin(BaseModel):
    username: str
    password: str

class UserRegister(BaseModel):
    username: str
    email: str
    password: str

@app.on_event("startup")
async def startup():
    # Создаем пул подключений при запуске приложения
    await db.get_async_pool()

@app.on_event("shutdown")
async def shutdown():
    # Закрываем пул при остановке приложения
    if db._pool:
        await db._pool.close()

@app.get("/")
async def root():
    return {"message": "Welcome to MEOWShop API V 0.1632.325.29GG3682.326230000VS029949.0000000001"}

@app.post("/login")
async def login(user: UserLogin):
    # Преобразуем функцию get_user_by_username для асинхронного использования
    pool = await db.get_async_pool()
    async with pool.acquire() as conn:
        row = await conn.fetchrow('SELECT * FROM "Users" WHERE username = $1', user.username)
        
        if not row:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password"
            )
        
        db_user = dict(row)
        
        if not security.verify_password(user.password, db_user["password"]):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Incorrect username or password"
            )
        
        token = security.create_access_token({"sub": user.username})
        return {"access_token": token, "token_type": "bearer"}

@app.post("/register")
async def register(user: UserRegister):
    # Проверка на существование пользователя
    pool = await db.get_async_pool()
    async with pool.acquire() as conn:
        existing_user = await conn.fetchrow('SELECT * FROM "Users" WHERE username = $1', user.username)
        
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )
        
        hashed_password = security.get_password_hash(user.password)
        
        # Создание нового пользователя
        row = await conn.fetchrow(
            'INSERT INTO "Users" (username, email, password, role) VALUES ($1, $2, $3, $4) RETURNING *',
            user.username, user.email, hashed_password, "user"
        )
        
        return {"message": "User created successfully", "user_id": row["user_id"]}

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

# JWT token для тестирования
# eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJNQU1VVCBSQUhBTCIsImV4cCI6MTc0ODU0NzI2Nn0.EygPdB_bdRcuUW2XkBCBEJj-pC6a9ps3lYMG2rtoznA