"""In-process rolling request limits for authenticated AI users."""

import math
import os
import threading
import time
from collections import deque


def _positive_env(name, default):
    value = os.getenv(name)
    if value is None:
        return default
    if not value.isascii() or not value.isdecimal() or not 1 <= int(value) <= 1_000_000:
        raise ValueError(f"{name} must be a positive integer no greater than 1000000")
    return int(value)


class RateLimitExceeded(Exception):
    def __init__(self, retry_after):
        self.retry_after = retry_after
        super().__init__("User request limit exceeded")


class RateLimiter:
    def __init__(self, summary_limit=3, quiz_limit=5, daily_limit=50, clock=time.monotonic):
        for value in (summary_limit, quiz_limit, daily_limit):
            if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
                raise ValueError("Rate limits must be positive integers")
        self._limits = {"summary": summary_limit, "quiz": quiz_limit}
        self._daily_limit = daily_limit
        self._clock = clock
        self._users = {}
        self._lock = threading.Lock()

    @classmethod
    def from_env(cls):
        return cls(
            summary_limit=_positive_env("RATE_LIMIT_SUMMARY_PER_MINUTE", 3),
            quiz_limit=_positive_env("RATE_LIMIT_QUIZ_PER_MINUTE", 5),
            daily_limit=_positive_env("RATE_LIMIT_AI_PER_DAY", 50),
        )

    def check_and_record(self, uid, feature):
        if not isinstance(uid, str) or not uid.strip() or feature not in self._limits:
            raise ValueError("A verified user and valid AI feature are required")
        with self._lock:
            now = self._clock()
            # Expired entries are removed for every user, including inactive users.
            for user, records in list(self._users.items()):
                while records and records[0][0] <= now - 86400:
                    records.popleft()
                if not records:
                    del self._users[user]

            records = self._users.get(uid, deque())
            recent = [timestamp for timestamp, kind in records
                      if kind == feature and timestamp > now - 60]
            waits = []
            if len(recent) >= self._limits[feature]:
                waits.append(recent[-self._limits[feature]] + 60 - now)
            if len(records) >= self._daily_limit:
                waits.append(records[-self._daily_limit][0] + 86400 - now)
            if waits:
                raise RateLimitExceeded(max(1, math.ceil(max(waits))))
            records.append((now, feature))
            self._users[uid] = records
