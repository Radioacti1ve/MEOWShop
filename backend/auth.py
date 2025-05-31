from fastapi import APIRouter, HTTPException, status, Depends
from pydantic import BaseModel
import security, db
from fastapi.security import OAuth2PasswordBearer, HTTPBearer

router = APIRouter()

security_scheme = HTTPBearer()
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login")

class UserLogin(BaseModel):
    username: str
    password: str

class UserRegister(BaseModel):
    username: str
    email: str
    password: str

@router.post("/login")
async def login(user: UserLogin):
    db_user = await db.get_user_by_username(user.username)
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

@router.post("/register")
async def register(user: UserRegister):
    try:
        existing_user = await db.get_user_by_username(user.username)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )
        hashed_password = security.get_password_hash(user.password)
        new_user = await db.create_user(user.username, user.email, hashed_password)
        return {"message": "User created successfully", "user_id": new_user["user_id"]}
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Internal error: {e}"
        )


@router.get("/protected", dependencies=[Depends(security_scheme)])
async def protected_route(token: str = Depends(oauth2_scheme)):
    payload = security.verify_token(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"}
        )
    return {"message": "This is a protected route", "user": payload["sub"]}
