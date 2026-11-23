import unittest

from backend.main import normalize_question_difficulties


class DifficultyNormalizationTest(unittest.TestCase):
    def test_normalizes_only_difficulty(self):
        questions = [
            {"question": "Q", "answer": "A", "difficulty": value}
            for value in ("easy", "medium", "hard", "invalid", None, [])
        ] + [{"question": "Q", "answer": "A"}, "invalid question"]
        result = normalize_question_difficulties(questions)
        self.assertEqual(
            [q["difficulty"] for q in result[:-1]],
            ["easy", "medium", "hard", "unspecified", "unspecified", "unspecified", "unspecified"],
        )
        for question in result[:-1]:
            self.assertEqual({k: v for k, v in question.items() if k != "difficulty"},
                             {"question": "Q", "answer": "A"})
        self.assertEqual(result[-1], "invalid question")


if __name__ == "__main__":
    unittest.main()
