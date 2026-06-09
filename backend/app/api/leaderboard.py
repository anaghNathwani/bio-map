from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.database import get_db
from app.models.user import User

router = APIRouter(prefix="/leaderboard", tags=["leaderboard"])


@router.get("")
async def leaderboard(limit: int = 50, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(User.username, User.annotation_count)
        .order_by(User.annotation_count.desc())
        .limit(limit)
    )
    return [{"username": row[0], "annotation_count": row[1]} for row in result.all()]
