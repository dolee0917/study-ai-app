
import os

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from google import genai

load_dotenv()

api_key = os.getenv("GEMINI_API_KEY")

app = FastAPI()


# Flutter에서 전달할 데이터 구조
class SummaryRequest(BaseModel):
    text: str = Field(min_length=10, max_length=30000)
    
class QuizRequest(BaseModel):
    text: str = Field(min_length=10, max_length=30000)


@app.get("/")
def home():
    return {"message": "AI 학습 튜터 서버가 정상적으로 실행 중입니다!"}


@app.post("/summarize")
def summarize(request: SummaryRequest):
    if not api_key:
        raise HTTPException(
            status_code=500,
            detail="Gemini API 키가 설정되지 않았습니다."
        )

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

        response = client.models.generate_content(
        model="gemini-3.5-flash-lite",
        contents=prompt
    )

        if not response.text:
            raise HTTPException(
                status_code=502,
                detail="Gemini가 빈 응답을 반환했습니다."
            )

        return {"summary": response.text}

    except HTTPException:
        raise
    except Exception as e:
        print(f"Gemini API 오류: {e}")
        raise HTTPException(
            status_code=502,
            detail="AI 요약 생성에 실패했습니다."
        )
        
        

@app.post("/generate-quiz")
def generate_quiz(request: QuizRequest):
    if not api_key:
        raise HTTPException(
            status_code=500,
            detail="Gemini API 키가 설정되지 않았습니다."
        )

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
      "explanation": "정답 해설"
    }},
    {{
      "type": "short_answer",
      "question": "문제 내용",
      "options": [],
      "answer": "정답",
      "explanation": "정답 해설"
    }}
  ]
}}

[강의자료]
{request.text}
"""

        response = client.models.generate_content(
            model="gemini-3.5-flash-lite",
            contents=prompt,
            config={
                "response_mime_type": "application/json"
            }
        )

        if not response.text:
            raise HTTPException(
                status_code=502,
                detail="Gemini가 빈 응답을 반환했습니다."
            )

        import json

        quiz_data = json.loads(response.text)

        if (
            not isinstance(quiz_data, dict)
            or not isinstance(quiz_data.get("questions"), list)
        ):
            raise ValueError("문제 데이터 형식이 올바르지 않습니다.")

        return quiz_data

    except HTTPException:
        raise
    except Exception as e:
        print(f"복습 문제 생성 오류: {e}")
        raise HTTPException(
            status_code=502,
            detail="복습 문제 생성에 실패했습니다."
        )

