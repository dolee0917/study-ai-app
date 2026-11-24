
import os
import time
import json

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field
from google import genai
from google.genai import errors

load_dotenv()

api_key = os.getenv("GEMINI_API_KEY")

app = FastAPI()

AI_ERRORS = {
    "AI_UNAVAILABLE": (503, "AI 서버에 요청이 집중되고 있습니다. 잠시 후 다시 시도해주세요."),
    "AI_RATE_LIMIT": (429, "AI 서비스 사용량 제한에 도달했습니다. 잠시 후 다시 시도해주세요."),
    "AI_MODEL_NOT_FOUND": (502, "AI 서비스 설정에 문제가 발생했습니다."),
    "AI_AUTH_ERROR": (502, "AI 서비스 연결 설정에 문제가 발생했습니다."),
    "AI_EMPTY_RESPONSE": (502, "AI가 결과를 생성하지 못했습니다. 다시 시도해주세요."),
    "AI_INVALID_RESPONSE": (502, "AI가 생성한 결과의 형식이 올바르지 않습니다. 다시 시도해주세요."),
    "AI_CONFIG_ERROR": (500, "AI 서비스 설정에 문제가 발생했습니다."),
    "AI_UNKNOWN_ERROR": (502, "AI 결과 생성 중 오류가 발생했습니다. 다시 시도해주세요."),
}


class AIError(HTTPException):
    def __init__(self, code, feature):
        status, message = AI_ERRORS[code]
        self.code = code
        print(f"ai feature={feature} error={code} http_status={status}")
        super().__init__(status_code=status, detail=message)


@app.exception_handler(AIError)
async def ai_error_handler(request, exc):
    return JSONResponse(status_code=exc.status_code,
                        content={"detail": exc.detail, "code": exc.code})


def gemini_error_code(error):
    return {503: "AI_UNAVAILABLE", 429: "AI_RATE_LIMIT", 404: "AI_MODEL_NOT_FOUND",
            401: "AI_AUTH_ERROR", 403: "AI_AUTH_ERROR"}.get(error.code, "AI_UNKNOWN_ERROR")


def call_gemini_with_retry(call, *args, **kwargs):
    """Retry Gemini HTTP 503 responses up to three times."""
    feature = kwargs.pop("_feature", "unknown")
    model = kwargs.get("model", "unknown")
    delays = (2, 4, 8)
    for attempt in range(len(delays) + 1):
        try:
            return call(*args, **kwargs)
        except errors.APIError as error:
            print(f"ai feature={feature} model={model} gemini_status={error.code} retries={attempt}")
            if error.code != 503 or attempt == len(delays):
                raise
            time.sleep(delays[attempt])


# Flutter에서 전달할 데이터 구조
class SummaryRequest(BaseModel):
    text: str = Field(min_length=10, max_length=30000)
    
class QuizRequest(BaseModel):
    text: str = Field(min_length=10, max_length=30000)


def normalize_question_difficulties(questions):
    for question in questions:
        if isinstance(question, dict):
            difficulty = question.get("difficulty")
            if not isinstance(difficulty, str) or difficulty not in ("easy", "medium", "hard"):
                question["difficulty"] = "unspecified"
    return questions


def normalize_question_concepts(questions):
    for question in questions:
        if isinstance(question, dict):
            for field in ("concept", "subConcept"):
                value = question.get(field)
                question[field] = (
                    " ".join(value.split()) or None if isinstance(value, str) else None
                )
    return questions


@app.get("/")
def home():
    return {"message": "AI 학습 튜터 서버가 정상적으로 실행 중입니다!"}


@app.post("/summarize")
def summarize(request: SummaryRequest):
    if not api_key:
        raise AIError("AI_CONFIG_ERROR", "summary")

    try:
        client = genai.Client(api_key=api_key)

        prompt = f"""
당신은 대학생의 학습을 돕는 AI 튜터입니다.

다음 강의자료를 읽고 시험 공부에 도움이 되도록
한국어로 핵심 내용을 요약해주세요.

요약 규칙:
1. 강의자료의 핵심 개념을 정리하세요.
2. 중요한 용어와 정의를 설명하세요.
3. 이해하기 어려운 개념은 쉽게 설명하세요.
4. 시험 대비에 중요한 내용을 구분하세요.
5. 강의자료에 없는 내용은 임의로 만들어내지 마세요.

[강의자료]
{request.text}
"""

        print("요약 주 모델 호출: gemini-3.8-flash")
        try:
            response = call_gemini_with_retry(
                client.models.generate_content,
                model="gemini-3.8-flash",
                contents=prompt,
                _feature="summary",
            )
        except errors.APIError as error:
            if error.code != 503:
                raise
            print("요약 주 모델 503 재시도 실패: 대체 모델로 전환")
            try:
                response = client.models.generate_content(
                    model="gemini-3.5-flash-lite",
                    contents=prompt,
                )
                if not response.text:
                    raise AIError("AI_EMPTY_RESPONSE", "summary")
                print("요약 대체 모델 호출 성공")
            except errors.APIError as error:
                print(f"ai feature=summary model=gemini-3.5-flash-lite gemini_status={error.code} retries=0 fallback=true")
                print("요약 대체 모델 호출 실패")
                raise
            except Exception:
                print("요약 대체 모델 호출 실패")
                raise

        if not response.text:
            raise AIError("AI_EMPTY_RESPONSE", "summary")

        return {"summary": response.text}

    except HTTPException:
        raise
    except errors.APIError as error:
        raise AIError(gemini_error_code(error), "summary") from None
    except Exception:
        print("Gemini 요약 생성 오류")
        raise AIError("AI_UNKNOWN_ERROR", "summary") from None
        
        

@app.post("/generate-quiz")
def generate_quiz(request: QuizRequest):
    if not api_key:
        raise AIError("AI_CONFIG_ERROR", "quiz")

    try:
        client = genai.Client(api_key=api_key)

        prompt = f"""
당신은 대학생의 시험 대비를 돕는 AI 튜터입니다.

다음 강의자료를 바탕으로 복습 문제를 생성해주세요.

문제 생성 규칙:
1. 객관식 5문제와 주관식 3문제를 생성하세요.
2. 객관식은 4개의 선택지를 제공하세요.
3. 각 문제에 정답과 자세한 해설을 포함하세요.
4. 강의자료의 핵심 개념을 중심으로 출제하세요.
5. 강의자료에 없는 내용을 임의로 만들어내지 마세요.
6. 모든 문제는 한국어로 작성하세요.
7. 반드시 아래 JSON 형식으로만 응답하세요.
8. JSON 외에 Markdown 코드 블록이나 설명을 넣지 마세요.
9. 각 문제의 난이도를 판단하여 difficulty에 easy, medium, hard 중 하나를 넣으세요.
   easy: 핵심 용어, 정의, 기본 개념 확인
   medium: 개념 간 관계 이해 및 기본 적용
   hard: 여러 개념을 결합한 응용·추론

개념 생성 규칙 (객관식과 주관식의 모든 문제에 적용):
1. concept는 문제가 평가하는 주요 학습 개념입니다.
2. subConcept는 그 핵심 개념에서 평가하는 구체적인 지식, 원리, 특징 또는 계산 방법입니다.
3. 두 개념 모두 입력된 강의자료에 근거해야 하며 자료에 없는 개념을 만들어내지 마세요.
4. 과목명이나 단원 전체처럼 지나치게 포괄적인 이름과 문제 문장 전체를 사용하지 마세요.
5. 같은 핵심 개념을 평가하는 문제에는 이 응답 안에서 동일한 concept 이름을 사용하세요.
6. 같은 세부 개념에는 가능한 한 동일한 표현을 사용하세요.
7. 번호나 불필요한 설명 없이 간결한 명사형으로 작성하세요.
8. 한국어를 기본으로 하되 자료에 포함된 LRU, FIFO, TCP 같은 기술 용어와 약어는 유지하세요.
9. concept와 subConcept는 각각 하나의 문자열로 반환하고 배열이나 객체를 사용하지 마세요.

JSON 형식:
{{
  "questions": [
    {{
      "type": "multiple_choice",
      "question": "문제 내용",
      "options": [
        "선택지 1",
        "선택지 2",
        "선택지 3",
        "선택지 4"
      ],
      "answer": "선택지 1",
      "explanation": "정답 해설",
      "difficulty": "medium",
      "concept": "핵심 개념",
      "subConcept": "세부 개념"
    }},
    {{
      "type": "short_answer",
      "question": "문제 내용",
      "options": [],
      "answer": "정답",
      "explanation": "정답 해설",
      "difficulty": "medium",
      "concept": "핵심 개념",
      "subConcept": "세부 개념"
    }}
  ]
}}

[강의자료]
{request.text}
"""

        response = call_gemini_with_retry(
            client.models.generate_content,
            model="gemini-3.5-flash-lite",
            contents=prompt,
            config={
                "response_mime_type": "application/json"
            },
            _feature="quiz",
        )

        if not response.text:
            raise AIError("AI_EMPTY_RESPONSE", "quiz")

        try:
            quiz_data = json.loads(response.text)
        except (json.JSONDecodeError, TypeError):
            raise AIError("AI_INVALID_RESPONSE", "quiz") from None

        if (
            not isinstance(quiz_data, dict)
            or not isinstance(quiz_data.get("questions"), list)
        ):
            raise AIError("AI_INVALID_RESPONSE", "quiz")

        normalize_question_difficulties(quiz_data["questions"])
        normalize_question_concepts(quiz_data["questions"])
        return quiz_data

    except HTTPException:
        raise
    except errors.APIError as error:
        raise AIError(gemini_error_code(error), "quiz") from None
    except Exception:
        raise AIError("AI_UNKNOWN_ERROR", "quiz") from None

