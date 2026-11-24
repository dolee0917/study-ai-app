import json
import unittest
from unittest.mock import Mock, patch

from backend.main import (
    QuizRequest,
    generate_quiz,
    normalize_question_concepts,
    normalize_question_difficulties,
)


class ConceptNormalizationTest(unittest.TestCase):
    def test_preserves_both_question_types_and_existing_fields(self):
        questions = [
            {"type": "multiple_choice", "question": "Q1", "options": ["A"],
             "answer": "A", "explanation": "E", "difficulty": "easy",
             "concept": " 페이지  교체 ", "subConcept": " LRU\t 교체\n기준 "},
            {"type": "short_answer", "question": "Q2", "options": [],
             "answer": "A2", "explanation": "E2", "difficulty": "hard",
             "concept": "프로세스 동기화", "subConcept": "세마포어"},
        ]
        originals = [dict(question) for question in questions]
        self.assertIs(normalize_question_concepts(questions), questions)
        self.assertEqual(questions[0]["concept"], "페이지 교체")
        self.assertEqual(questions[0]["subConcept"], "LRU 교체 기준")
        self.assertEqual(questions[1]["concept"], "프로세스 동기화")
        self.assertEqual(questions[1]["subConcept"], "세마포어")
        for actual, original in zip(questions, originals):
            for key in original.keys() - {"concept", "subConcept"}:
                self.assertEqual(actual[key], original[key])

    def test_missing_empty_and_non_string_values_are_null(self):
        values = ["", "  \t\n", 0, 1.5, [], {}, True, False, None]
        questions = [{"concept": value, "subConcept": value} for value in values]
        questions.extend([{}, "invalid question"])
        normalize_question_concepts(questions)
        for question in questions[:-1]:
            self.assertIsNone(question["concept"])
            self.assertIsNone(question["subConcept"])
        self.assertEqual(questions[-1], "invalid question")

    def test_fields_are_independent_and_difficulty_is_unchanged(self):
        questions = [
            {"concept": " 유효 개념 ", "subConcept": [], "difficulty": "easy"},
            {"concept": False, "subConcept": " 세부  개념 ", "difficulty": "bad"},
        ]
        normalize_question_difficulties(questions)
        normalize_question_concepts(questions)
        self.assertEqual(questions, [
            {"concept": "유효 개념", "subConcept": None, "difficulty": "easy"},
            {"concept": None, "subConcept": "세부 개념", "difficulty": "unspecified"},
        ])

    @patch("backend.main.genai.Client")
    @patch("backend.main.api_key", "test-key")
    def test_generate_quiz_normalizes_legacy_response_and_requests_both_fields(self, client):
        questions = [
            {"type": "multiple_choice", "question": "Q", "options": ["A"],
             "answer": "A", "explanation": "E", "difficulty": "medium"},
            {"type": "short_answer", "question": "S", "options": [],
             "answer": "A", "explanation": "E", "difficulty": "bad",
             "concept": " 핵심 ", "subConcept": " 세부  개념 "},
        ]
        generate = client.return_value.models.generate_content
        generate.return_value = Mock(text=json.dumps({"questions": questions}))
        result = generate_quiz(QuizRequest(text="학습 자료입니다. 충분한 길이입니다."))
        self.assertEqual(len(result["questions"]), 2)
        self.assertIsNone(result["questions"][0]["concept"])
        self.assertIsNone(result["questions"][0]["subConcept"])
        self.assertEqual(result["questions"][0]["answer"], "A")
        self.assertEqual(result["questions"][1]["concept"], "핵심")
        self.assertEqual(result["questions"][1]["subConcept"], "세부 개념")
        self.assertEqual(result["questions"][1]["difficulty"], "unspecified")
        generate.assert_called_once()
        kwargs = generate.call_args.kwargs
        self.assertEqual(kwargs["model"], "gemini-3.5-flash-lite")
        prompt = kwargs["contents"]
        self.assertIn("객관식과 주관식의 모든 문제에 적용", prompt)
        example = prompt.split("JSON 형식:", 1)[1].split("[강의자료]", 1)[0]
        examples = json.loads(example)["questions"]
        self.assertEqual([item["type"] for item in examples], ["multiple_choice", "short_answer"])
        for item in examples:
            self.assertIsInstance(item["concept"], str)
            self.assertIsInstance(item["subConcept"], str)


if __name__ == "__main__":
    unittest.main()
