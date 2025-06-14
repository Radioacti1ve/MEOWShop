from pydantic import BaseModel, EmailStr
from typing import Optional
from datetime import datetime

class UserLogin(BaseModel):
    username: str
    password: str

class UserRegister(BaseModel):
    username: str
    email: EmailStr
    password: str

class Token(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int

class TokenRefresh(BaseModel):
    refresh_token: str

class SellerRegister(UserRegister):
    pass

class PendingSellerResponse(BaseModel):
    pending_seller_id: int
    user_id: int
    status: str
    created_at: datetime
    updated_at: datetime
    admin_comment: Optional[str]

class SellerApproval(BaseModel):
    status: str
    admin_comment: Optional[str] = None

class AdminRegister(UserRegister):
    pass

class PendingAdminResponse(BaseModel):
    pending_admin_id: int
    user_id: int
    status: str
    created_at: datetime
    updated_at: datetime
    approver_comment: Optional[str] = None

class AdminApproval(BaseModel):
    status: str
    approver_comment: Optional[str] = None
