from datetime import datetime, timedelta
from jose import JWTError, jwt
from passlib.context import CryptContext
import os
from dotenv import load_dotenv
from typing import Optional, Tuple
import redis
from fastapi import HTTPException, status
from fastapi.security import HTTPBearer
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

load_dotenv()

SECRET_KEY = os.getenv("SECRET_KEY", "your-secret-key")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 30
REFRESH_TOKEN_EXPIRE_DAYS = 30

# Password hashing
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")

# Token creation
oauth2_scheme = HTTPBearer(
    scheme_name="Bearer Authentication",
    description="JWT Bearer token",
    auto_error=True
)

# Redis client for blacklisted tokens
redis_client = redis.Redis(host='redis', port=6379, db=0, decode_responses=True)

def verify_password(plain_password: str, stored_password: str) -> bool:
    """Verify a password against stored password (hash or plain text during transition)."""
    # Временное решение: если пароль в базе начинается с $2b$ (bcrypt hash), используем bcrypt
    # иначе сравниваем как обычный текст
    if stored_password.startswith('$2b$'):
        return pwd_context.verify(plain_password, stored_password)
    return plain_password == stored_password  # Для старых паролей в базе

def get_password_hash(password: str) -> str:
    """Generate password hash."""
    return pwd_context.hash(password)

def create_tokens(data: dict) -> Tuple[str, str, int]:
    """Create access and refresh tokens."""
    access_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    refresh_expires = timedelta(days=REFRESH_TOKEN_EXPIRE_DAYS)
    
    access_exp = datetime.utcnow() + access_expires
    refresh_exp = datetime.utcnow() + refresh_expires
    
    to_encode = data.copy()
    to_encode.update({"exp": access_exp, "type": "access"})
    access_token = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    
    to_encode.update({"exp": refresh_exp, "type": "refresh"})
    refresh_token = jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)
    
    return access_token, refresh_token, int(access_expires.total_seconds())

def verify_token(token: str, token_type: str = "access") -> dict:
    """Verify JWT token."""
    try:
        # Проверяем blacklist
        try:
            if redis_client.get(f"blacklist:{token}"):
                raise HTTPException(
                    status_code=status.HTTP_401_UNAUTHORIZED,
                    detail="Token has been revoked",
                    headers={"WWW-Authenticate": "Bearer"},
                )
        except redis.RedisError as e:
            logger.error(f"Redis error while checking blacklist: {str(e)}")
            # Продолжаем выполнение, так как ошибка Redis не должна блокировать доступ
        
        # Декодируем JWT
        try:
            payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        except JWTError as e:
            logger.error(f"JWT verification error: {str(e)}")
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Could not validate credentials",
                headers={"WWW-Authenticate": "Bearer"},
            )
            
        # Проверяем тип токена
        if payload.get("type") != token_type:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Invalid token type. Expected {token_type}",
                headers={"WWW-Authenticate": "Bearer"},
            )
            
        # Проверяем claims
        if not payload or not payload.get("sub"):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token claims",
                headers={"WWW-Authenticate": "Bearer"},
            )
            
        return payload
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error during token verification: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

def blacklist_token(token: str, expires_in: int) -> None:
    """Add a token to the blacklist."""
    try:
        redis_client.setex(f"blacklist:{token}", expires_in, "1")
    except redis.RedisError as e:
        logger.error(f"Redis error while blacklisting token: {e}")
