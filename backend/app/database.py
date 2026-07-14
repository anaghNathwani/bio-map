from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from sqlalchemy.orm import DeclarativeBase

from app.config import settings

# Supabase's pgbouncer pooler requires statement_cache_size=0 for asyncpg.
# For direct connections (local/dev) this is a no-op.
_connect_args = {"statement_cache_size": 0} if "pooler.supabase.com" in settings.database_url else {}
engine = create_async_engine(settings.database_url, echo=False, connect_args=_connect_args)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        yield session
