import logging
from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from slowapi import Limiter
from slowapi.util import get_remote_address

from app.database import get_db
from app.models.user import User

router = APIRouter(prefix="/leaderboard", tags=["leaderboard"])
limiter = Limiter(key_func=get_remote_address)
logger = logging.getLogger(__name__)


@router.get("")
@limiter.limit("30/minute")
async def leaderboard(
    request: Request,
    limit: int = Query(50, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(User.username, User.annotation_count)
        .order_by(User.annotation_count.desc())
        .limit(limit)
    )
    return [{"username": row[0], "annotation_count": row[1]} for row in result.all()]
