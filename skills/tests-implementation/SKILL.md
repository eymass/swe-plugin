
---
name: tests-implementation
description: "Use this skill whenever the user asks about testing, writing tests, what to test, test strategy, test coverage, or how to validate any piece of code — regardless of type (API, service, domain logic, CLI, worker, utility). Triggers include: 'write tests', 'add tests', 'how do I test this', 'what should I test', 'test coverage', 'test strategy', 'is this testable', 'unit vs integration', or any request to validate behavior of code. Also trigger when reviewing code and noticing missing or low-quality tests. Apply the principal engineer mindset: push back on naive unit tests, always ask what the system promises and what would hurt if it broke silently. Do NOT write tests that chase coverage metrics. Every test must earn its place."
---

# Testing — Principal Engineer Mindset

> **Tests are not proof that code runs. They are proof that the system keeps its promises.**  
> A test suite with 90% coverage that misses every real bug is a liability, not an asset.

---

## The Mindset Shift

Stop asking: *"Did I test every function?"*  
Start asking: *"If this broke silently in production, would my tests catch it?"*

After finishing any implementation, answer these before writing a single test:

```
1. What does this code PROMISE to the code that calls it?
2. What are the realistic ways it fails — and what should happen?
3. What invariants must hold regardless of input or future refactors?
4. What integration point could silently corrupt state or data?
```

Write tests for those answers. Skip everything else.

---

## The Decision Filter

Run every test idea through this before writing it:

```
Is this a public contract behavior?               → Contract test
Can this fail and leave corrupt or partial state? → Failure flow test
Is this a business rule that must always hold?    → Invariant test
Did this already break in production?             → Regression test
Is this an internal implementation detail?        → SKIP
Would this test survive a correct refactor?       → If no → SKIP
```

> If your test would still pass after you introduced a real bug — delete it.

---

## The Five Test Types

### 1. Contract Tests — "Does it work?"

**What:** Prove the public interface fulfills its documented promise on the happy path.  
**Where:** `tests/integration/` for I/O-bound, `tests/unit/` for pure logic.  
**How many:** One per public behavior. Not one per function. Not one per line.

```python
# API contract
async def test_create_user_returns_id_and_persists(client, db):
    res = await client.post("/users", json={"name": "Alice", "email": "a@b.com"})
    assert res.status_code == 201
    assert res.json()["id"] is not None
    doc = await db["users"].find_one({"_id": ObjectId(res.json()["id"])})
    assert doc is not None                       # HTTP 200 ≠ data persisted

# Service contract
def test_price_calculator_applies_discount():
    assert calculate_price(base=100, discount=0.2) == 80.0

# Worker/queue contract
async def test_order_worker_marks_order_as_processed(worker, db):
    order_id = await seed_order(db, status="pending")
    await worker.process(order_id)
    doc = await db["orders"].find_one({"_id": ObjectId(order_id)})
    assert doc["status"] == "processed"
```

---

### 2. Failure Flow Tests — "Does it fail correctly?"

**What:** Prove the system rejects bad state cleanly — right error, right status, no side effects.  
**The key question:** Was any partial state written? Was anything mutated that shouldn't be?

```python
# Rejects invalid input before touching DB
async def test_create_user_with_empty_name_rejects_early(client, db):
    res = await client.post("/users", json={"name": "", "email": "a@b.com"})
    assert res.status_code == 422
    assert await db["users"].count_documents({}) == 0    # no ghost writes

# Handles missing resource correctly
async def test_get_user_not_found_returns_404(client):
    res = await client.get(f"/users/{ObjectId()}")
    assert res.status_code == 404

# Fails on constraint violation without corrupting state
async def test_duplicate_email_rejected(client, db):
    await seed_user(db, email="a@b.com")
    res = await client.post("/users", json={"name": "Bob", "email": "a@b.com"})
    assert res.status_code == 409
    assert await db["users"].count_documents({}) == 1    # original unchanged

# Service-level failure
def test_payment_raises_on_insufficient_funds():
    with pytest.raises(InsufficientFundsError):
        process_payment(account_id="x", amount=10_000)
```

**Cover these failure categories:**
- Invalid or missing input (422)
- Missing resource (404)
- Duplicate / constraint violation (409)
- Unauthorized / wrong role (403)
- Invalid state transitions
- External service failures — what does the caller actually get?

---

### 3. Invariant Tests — "Is this always true?"

**What:** Protect business rules and data integrity guarantees that must hold regardless of input or refactors.  
**Where:** `tests/domain/` — pure logic, no I/O, runs in milliseconds.  
**When:** Ask — *"if someone rewrites this module, what could silently break?"*

```python
# Financial invariants
def test_final_price_never_negative():
    assert build_order(total=50, discount=200).final_price >= 0

def test_tax_never_applied_to_free_items():
    assert OrderLine(price=0, qty=3).tax == 0

# State machine invariants
def test_completed_order_cannot_be_cancelled():
    order = Order(status=OrderStatus.COMPLETED)
    with pytest.raises(InvalidTransitionError):
        order.cancel()

def test_every_status_has_a_defined_transition_map():
    for status in OrderStatus:
        assert status in VALID_TRANSITIONS

# Concurrency invariants
@pytest.mark.asyncio
async def test_concurrent_stock_deductions_do_not_oversell(db):
    await db["items"].insert_one({"_id": "x", "qty": 5})
    await asyncio.gather(*[deduct_stock(db, "x", qty=1) for _ in range(20)])
    item = await db["items"].find_one({"_id": "x"})
    assert item["qty"] >= 0
```

---

### 4. Integration Tests — "Does it work with real infrastructure?"

**What:** Prove end-to-end behavior through real I/O — actual DB, actual HTTP, actual indexes.  
**Why real infra:** Mocks lie. Real MongoDB catches index violations, BSON type mismatches, TTL behavior, and aggregation edge cases. Real HTTP catches serialization bugs and middleware failures.

```python
# Real index enforcement — mock would silently pass
async def test_unique_email_index_enforced(db):
    await db["users"].create_index("email", unique=True)
    await db["users"].insert_one({"email": "a@b.com"})
    with pytest.raises(DuplicateKeyError):
        await db["users"].insert_one({"email": "a@b.com"})

# Full request/response cycle with pagination
async def test_pagination_returns_correct_page(client, db):
    for i in range(25):
        await seed_user(db, name=f"User {i}")
    res = await client.get("/users?page=2&size=10")
    assert res.status_code == 200
    assert len(res.json()["items"]) == 10
    assert res.json()["total"] == 25
```

**Setup — testcontainers (recommended for CI):**

```python
# conftest.py
@pytest.fixture(scope="session")
def mongo_container():
    with MongoDbContainer("mongo:7") as c:
        yield c.get_connection_url()

@pytest.fixture(scope="session")
async def db(mongo_container):
    client = AsyncIOMotorClient(mongo_container)
    yield client["test_db"]
    client.close()

@pytest.fixture(autouse=True)
async def clean_db(db):
    yield
    for name in await db.list_collection_names():
        await db[name].drop()

@pytest.fixture
async def client(db):
    app.dependency_overrides[get_db] = lambda: db
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()
```

> Use `mongomock-motor` locally for speed. Use `testcontainers` in CI for correctness.

---

### 5. Regression Tests — "Did this bug come back?"

**What:** Encode every production bug as a failing test before writing the fix.  
**Rule:** If the test doesn't fail before the fix — it's useless.  
**Where:** `tests/regression/` — one file per incident, named after the ticket.

```python
# tests/regression/test_gh_412_order_empty_status.py
# Bug: order status not updated when last item was removed

@pytest.mark.asyncio
async def test_order_becomes_empty_when_all_items_removed(client, db):
    order_id = await seed_order(db, items=["a"])
    await client.delete(f"/orders/{order_id}/items/a")
    doc = await db["orders"].find_one({"_id": ObjectId(order_id)})
    assert doc["status"] == "empty"
```

**Workflow:**
1. Reproduce the bug
2. Write the test — confirm it **fails**
3. Fix the code
4. Confirm the test passes
5. Never delete the test

---

## Seeding Test Data

Always seed directly into the DB for setup. Never chain API calls to set up state.

```python
# tests/factories.py
async def seed_user(db, **overrides) -> dict:
    doc = {"name": "Test User", "email": "test@example.com",
           "status": "active", "created_at": utc_now(), **overrides}
    result = await db["users"].insert_one(doc)
    return {**doc, "id": str(result.inserted_id)}

async def seed_order(db, **overrides) -> str:
    doc = {"user_id": "u1", "items": ["a"], "status": "open",
           "created_at": utc_now(), **overrides}
    result = await db["orders"].insert_one(doc)
    return str(result.inserted_id)
```

```python
# ✅ seed via DB — tests one thing
async def test_get_user(client, db):
    user = await seed_user(db, name="Alice")
    res = await client.get(f"/users/{user['id']}")
    assert res.status_code == 200

# ❌ seed via API — testing two things, fragile chain
async def test_get_user(client):
    create_res = await client.post("/users", json={...})   # failure here breaks unrelated test
    res = await client.get(f"/users/{create_res.json()['id']}")
```

---

## What to Skip

| Temptation | Why |
|---|---|
| Testing a Pydantic model parses a valid payload | The library is already tested |
| `assert service.save.was_called()` | Tests implementation, not behavior |
| Every permutation of valid input | One representative case is enough |
| Mocking the DB to test a repository | Misses real constraints — use testcontainers |
| Happy path with no DB state assertion | HTTP 200 doesn't mean data was saved |
| Testing private / internal helpers directly | Test through the public interface |
| 100% line coverage target | Chases noise, rewards padding |

---

## Project Structure

```
tests/
├── conftest.py              # DB, HTTP client, clean_db, shared fixtures
├── factories.py             # seed helpers per domain entity
│
├── integration/             # real HTTP + real DB — highest signal
│   ├── test_users_api.py
│   ├── test_orders_api.py
│   └── test_payments_api.py
│
├── domain/                  # pure business logic — fast, no I/O
│   ├── test_pricing_rules.py
│   ├── test_order_state_machine.py
│   └── test_discount_invariants.py
│
├── unit/                    # pure functions, algorithms, transformers
│   ├── test_slug_generator.py
│   └── test_date_utils.py
│
└── regression/              # one file per production incident
    ├── test_gh_412_order_empty_status.py
    └── test_gh_581_negative_balance.py
```

---

## The Ratio That Works

| Layer | Volume | Speed | Signal |
|---|---|---|---|
| Integration (real I/O) | Medium | Slow | Highest |
| Domain invariants | Small | Fast | High |
| Regression | Grows with incidents | Fast | Critical |
| Unit (pure logic only) | Minimal | Fast | Medium |

> More integration tests than unit tests.  
> Fewer total tests than you think you need.  
> Every test must earn its place.
