"""Firebase ID-token dependency for use by authenticated routes."""

from fastapi import Depends, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from firebase_admin import auth
from starlette.concurrency import run_in_threadpool

if __package__:
    from .firebase_admin_config import FirebaseConfigurationError, get_firebase_app
else:
    from firebase_admin_config import FirebaseConfigurationError, get_firebase_app


class FirebaseAuthError(HTTPException):
    def __init__(self, status_code, code, detail):
        self.code = code
        headers = {"WWW-Authenticate": "Bearer"} if status_code == 401 else None
        super().__init__(status_code=status_code, detail=detail, headers=headers)


async def firebase_auth_error_handler(request: Request, exc: FirebaseAuthError):
    return JSONResponse(
        status_code=exc.status_code,
        content={"detail": exc.detail, "code": exc.code},
        headers=exc.headers,
    )


_bearer = HTTPBearer(auto_error=False)


def _verify_token(token: str) -> str:
    try:
        app = get_firebase_app()
        claims = auth.verify_id_token(token, app=app, check_revoked=False)
    except FirebaseConfigurationError:
        raise FirebaseAuthError(503, "AUTH_CONFIG_ERROR", "인증 서비스 설정을 확인할 수 없습니다.") from None
    except auth.CertificateFetchError:
        raise FirebaseAuthError(503, "AUTH_UNAVAILABLE", "인증 서비스를 이용할 수 없습니다.") from None
    except auth.ExpiredIdTokenError:
        raise FirebaseAuthError(401, "AUTH_TOKEN_EXPIRED", "인증 토큰이 만료되었습니다.") from None
    except auth.InvalidIdTokenError:
        raise FirebaseAuthError(401, "AUTH_TOKEN_INVALID", "유효하지 않은 인증 토큰입니다.") from None
    except Exception:
        raise FirebaseAuthError(503, "AUTH_UNAVAILABLE", "인증 서비스를 이용할 수 없습니다.") from None

    uid = claims.get("uid") if isinstance(claims, dict) else None
    if not isinstance(uid, str) or not uid.strip() or len(uid) > 128:
        raise FirebaseAuthError(401, "AUTH_TOKEN_INVALID", "유효하지 않은 인증 토큰입니다.")
    return uid


async def require_firebase_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
) -> str:
    header = request.headers.get("Authorization")
    if header is None:
        raise FirebaseAuthError(401, "AUTH_MISSING", "인증 토큰이 필요합니다.")
    if (credentials is None or not credentials.credentials.strip()
            or any(char.isspace() for char in credentials.credentials)):
        raise FirebaseAuthError(401, "AUTH_INVALID_FORMAT", "Bearer 인증 형식이 올바르지 않습니다.")
    return await run_in_threadpool(_verify_token, credentials.credentials)
