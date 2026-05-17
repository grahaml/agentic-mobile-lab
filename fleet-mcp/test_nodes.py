import asyncio
import httpx
from server import mobile_security_review, mobile_write_unit_test

async def test_nodes():
    print("📡 Testing S20 (Security Review)...")
    code = "def login(user, pwd): return True # TODO: Fix hardcoded auth"
    result = await mobile_security_review(code)
    print(f"S20 Response:\n{result}\n")

    print("📡 Testing S10e (Unit Test)...")
    code = "def add(a, b): return a + b"
    result = await mobile_write_unit_test(code, "python")
    print(f"S10e Response:\n{result}\n")

if __name__ == "__main__":
    asyncio.run(test_nodes())
