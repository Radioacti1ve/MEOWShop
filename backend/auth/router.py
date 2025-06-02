from fastapi import APIRouter, Depends, HTTPException, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from .models import UserLogin, UserRegister, Token, TokenRefresh, SellerRegister, PendingSellerResponse, SellerApproval, AdminRegister, PendingAdminResponse, AdminApproval
from .security import oauth2_scheme
from . import security
import db
import logging
from typing import Annotated, List
from datetime import datetime
from .depends import get_current_user, require_role

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/auth",
    tags=["Authentication"],
    responses={404: {"description": "Not found"}},
)

@router.post("/login", response_model=Token, summary="User login")
async def login(user: UserLogin, request: Request):
    try:
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
        
        if not db_user["is_active"]:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="User is banned"
            )
        
        access_token, refresh_token, expires_in = security.create_tokens({"sub": user.username})
        ip_address = request.client.host
        user_agent = request.headers.get("user-agent", "unknown")

        async with db.pool.acquire() as conn:
            await conn.execute(
                '''
                INSERT INTO "Auth_events" (user_id, event_type, ip_address, user_agent)
                VALUES ($1, 'login', $2, $3)
                ''',
                db_user["user_id"], ip_address, user_agent
            )

        return {
            "access_token": access_token,
            "refresh_token": refresh_token,
            "token_type": "bearer",
            "expires_in": expires_in
        }
    except HTTPException as http_ex:
        logger.error(f"Login authentication error: {str(http_ex)}")
        raise http_ex
    except Exception as e:
        logger.error(f"Login error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/register", status_code=status.HTTP_201_CREATED, summary="Register new user")
async def register(user: UserRegister, request: Request):
    try:
        existing_user = await db.get_user_by_username(user.username)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )
        hashed_password = security.get_password_hash(user.password)
        new_user = await db.create_user(user.username, user.email, hashed_password)

        ip_address = request.client.host
        user_agent = request.headers.get("user-agent", "unknown")

        async with db.pool.acquire() as conn:
            await conn.execute(
                '''
                INSERT INTO "Auth_events" (user_id, event_type, ip_address, user_agent)
                VALUES ($1, 'register', $2, $3)
                ''',
                new_user["user_id"], ip_address, user_agent
            )
            
        return {"message": "User created successfully", "user_id": new_user["user_id"]}
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Registration error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.get("/me", summary="Get current user")
async def get_current_user(token: Annotated[HTTPAuthorizationCredentials, Depends(oauth2_scheme)]):
    try:
        payload = security.verify_token(token.credentials)
        if not payload:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token"
            )
        username = payload.get("sub")
        user = await db.get_user_by_username(username)
        if not user:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found"
            )
        user_data = dict(user)
        del user_data["password"]
        return user_data
    except HTTPException as e:
        logger.error(f"Authentication error: {str(e)}")
        raise e
    except Exception as e:
        logger.error(f"Get current user error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Could not validate credentials",
            headers={"WWW-Authenticate": "Bearer"},
        )

@router.post("/refresh", response_model=Token, summary="Refresh access token")
async def refresh_token(refresh_data: TokenRefresh):
    try:
        payload = security.verify_token(refresh_data.refresh_token, token_type="refresh")
        access_token, new_refresh_token, expires_in = security.create_tokens({"sub": payload["sub"]})
        try:
            exp = payload.get("exp", 0)
            now = datetime.utcnow().timestamp()
            ttl = int(exp - now)
            if ttl > 0:
                security.blacklist_token(refresh_data.refresh_token, ttl)
        except Exception as e:
            logger.warning(f"Error blacklisting old refresh token: {str(e)}")
            
        return {
            "access_token": access_token,
            "refresh_token": new_refresh_token,
            "token_type": "bearer",
            "expires_in": expires_in
        }
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Token refresh error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/logout", status_code=status.HTTP_200_OK, summary="Logout user")
async def logout(token: Annotated[HTTPAuthorizationCredentials, Depends(oauth2_scheme)]):
    try:
        payload = security.verify_token(token.credentials)
        exp = payload.get("exp", 0)
        now = datetime.utcnow().timestamp()
        ttl = int(exp - now)
        if ttl > 0:
            security.blacklist_token(token.credentials, ttl)
        return {"message": "Successfully logged out"}
    except Exception as e:
        logger.error(f"Logout error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/sellers/register", status_code=status.HTTP_201_CREATED, response_model=PendingSellerResponse)
async def register_seller(seller: SellerRegister):
    try:
        existing_user = await db.get_user_by_username(seller.username)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )

        hashed_password = security.get_password_hash(seller.password)
        new_user = await db.create_user(seller.username, seller.email, hashed_password)
        if not new_user:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create user account"
            )

        pending_seller = await db.create_pending_seller(user_id=new_user["user_id"])
        if not pending_seller:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create seller application"
            )

        return pending_seller

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Seller registration error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.get("/sellers/pending", response_model=List[PendingSellerResponse])
async def get_pending_sellers(
    current_user: Annotated[dict, Depends(require_role(["admin"]))]
):
    try:
        return await db.get_pending_sellers_by_status("pending")
    except Exception as e:
        logger.error(f"Error getting pending sellers: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/sellers/{pending_seller_id}/approve", response_model=PendingSellerResponse)
async def approve_seller(
    pending_seller_id: int,
    approval: SellerApproval,
    current_user: Annotated[dict, Depends(require_role(["admin"]))]
):
    try:
        pending_seller = await db.get_pending_seller(pending_seller_id)
        if not pending_seller:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Pending seller application not found"
            )

        if pending_seller["status"] != "pending":
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Application already {pending_seller['status']}"
            )

        updated_seller = await db.update_pending_seller_status(
            pending_seller_id=pending_seller_id,
            status=approval.status,
            admin_comment=approval.admin_comment
        )
        if not updated_seller:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to update seller status"
            )

        return updated_seller

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error approving seller: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.get("/sellers/application/status", response_model=PendingSellerResponse)
async def get_seller_application_status(
    current_user: Annotated[dict, Depends(get_current_user)]
):
    try:
        pending_seller = await db.get_pending_seller_by_user_id(current_user["user_id"])
        if not pending_seller:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No seller application found"
            )
        return pending_seller
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting seller application status: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/admins/register", status_code=status.HTTP_201_CREATED, response_model=PendingAdminResponse)
async def register_admin(admin: AdminRegister):
    try:
        existing_user = await db.get_user_by_username(admin.username)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )

        hashed_password = security.get_password_hash(admin.password)
        new_user = await db.create_user(admin.username, admin.email, hashed_password)
        if not new_user:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create user account"
            )
            
        existing_application = await db.get_pending_admin_by_user_id(new_user["user_id"])
        if existing_application:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="User already has a pending admin application"
            )

        pending_admin = await db.create_pending_admin(new_user["user_id"])
        if not pending_admin:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create admin application"
            )

        return pending_admin

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Admin registration error: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.get("/admins/pending", response_model=List[PendingAdminResponse])
async def get_pending_admins(
    current_user: Annotated[dict, Depends(require_role(["admin"]))]
):
    try:
        return await db.get_pending_admins_by_status("pending")
    except Exception as e:
        logger.error(f"Error getting pending admins: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.get("/admins/application/status", response_model=PendingAdminResponse)
async def get_admin_application_status(
    current_user: Annotated[dict, Depends(get_current_user)]
):
    try:
        pending_admin = await db.get_pending_admin_by_user_id(current_user["user_id"])
        if not pending_admin:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="No admin application found"
            )
        return pending_admin
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error getting admin application status: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.post("/admins/{pending_admin_id}/approve", response_model=PendingAdminResponse)
async def approve_admin(
    pending_admin_id: int,
    approval: AdminApproval,
    current_user: Annotated[dict, Depends(require_role(["admin"]))]
):
    try:
        existing_application = await db.get_pending_admin_by_id(pending_admin_id)
        if not existing_application:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Admin application not found"
            )

        updated_admin = await db.update_pending_admin_status(
            pending_admin_id=pending_admin_id,
            status=approval.status,
            approver_comment=approval.approver_comment
        )
        if not updated_admin:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to update admin status"
            )

        return updated_admin

    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error approving admin: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )
