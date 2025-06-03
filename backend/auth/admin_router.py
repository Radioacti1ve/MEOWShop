from fastapi import APIRouter, Depends, HTTPException, status
from typing import List, Annotated
import logging
import db
from .models import AdminRegister, AdminApproval, PendingAdminResponse
from .security import get_password_hash
from .depends import get_current_user, require_role

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

router = APIRouter(
    prefix="/auth/admins",
    tags=["Admin Management"],
    responses={404: {"description": "Not found"}}
)

@router.post("/register", status_code=status.HTTP_201_CREATED, response_model=PendingAdminResponse)
async def register_admin(admin: AdminRegister):
    try:
        existing_user = await db.get_user_by_username(admin.username)
        if existing_user:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Username already registered"
            )

        hashed_password = get_password_hash(admin.password)
        new_user = await db.create_user(admin.username, admin.email, hashed_password)
        if not new_user:
            raise HTTPException(
                status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
                detail="Failed to create user account"
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

@router.get("/pending", response_model=List[PendingAdminResponse])
async def get_pending_admins(
    current_user: Annotated[dict, Depends(require_role(["super_admin"]))]
):
    try:
        return await db.get_pending_admins_by_status("pending")
    except Exception as e:
        logger.error(f"Error getting pending admins: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Internal server error"
        )

@router.get("/status", response_model=PendingAdminResponse)
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

@router.post("/{pending_admin_id}/approve", response_model=PendingAdminResponse)
async def approve_admin(
    pending_admin_id: int,
    approval: AdminApproval,
    current_user: Annotated[dict, Depends(require_role(["super_admin"]))]
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
