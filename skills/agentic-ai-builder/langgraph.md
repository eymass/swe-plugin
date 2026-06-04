# The 10 Pillars of Building Agents — Technical Implementation Reference
### LangGraph + LangChain 1.0 (v1.2.x era)

> **Scope.** Each pillar lists the **classes / types / functions** you import and call, the **knobs that matter**, and **minimal code**. This is a "what do I actually type" reference, not a tutorial.
>
> **Version caveat (read once).** Targets LangGraph 1.2.x / LangChain 1.0. Two things moved during v1.x and you should confirm against your installed version: (1) the prebuilt agent now lives at `langchain.agents.create_agent` (the old `langgraph.prebuilt.create_react_agent` is deprecated); (2) middleware classes live under `langchain.agents.middleware` but the exact submodule has shifted — verify with `python -c "import langchain.agents.middleware as m; print(dir(m))"`. Pin `langgraph-prebuilt` (the 1.0.2 `ToolNode.afunc` signature change is a known breaker).

---

## Core imports (the ones you'll use everywhere)

```python
from langgraph.graph import StateGraph, START, END
from langgraph.graph.message import add_messages
from langgraph.types import Command, Send, interrupt, RetryPolicy
from langchain.agents import create_agent           # LC 1.0 prebuilt loop
```

---

# TIER 1 — FOUNDATION

## Pillar 1 — State, Channels, Reducers

**API surface**
- `StateGraph(state_schema)` — `state_schema` is a `TypedDict` / `pydantic.BaseModel` / `dataclass`.
- Reducers via `typing.Annotated[T, reducer]`:
  - `add_messages` — append + merge by message ID (handles updates/removals).
  - `operator.add` — list concatenation.
  - custom `Callable[[T, T], T]`.
- `Overwrite(value)` (v1.2) — bypass a channel's reducer to set it directly. Two `Overwrite` writes to one channel in a single superstep → `InvalidUpdateError`.

**Minimal**
```python
import operator
from typing import Annotated, TypedDict
from langgraph.graph.message import add_messages

class State(TypedDict):
    messages: Annotated[list, add_messages]
    scratch:  Annotated[list[str], operator.add]   # parallel-safe append
    answer:   str                                   # no reducer = last-write-wins, single writer only
```

**Knobs that matter**
- A channel written by >1 concurrent node **must** have a reducer, or you get `InvalidUpdateError`.
- Multiple state schemas: pass `input_schema=` / `output_schema=` to `StateGraph` to expose a narrow public contract while keeping a wide internal state.

**Trap.** Single-writer fields silently work until you parallelize, then throw. Decide the reducer when you declare the field, not when it breaks.

---

## Pillar 2 — Graph Construction, Edges, Command

**API surface**
- `builder.add_node(name, fn)` — `fn: (state) -> dict | Command`.
- `builder.add_edge(src, dst)`; `START` / `END` sentinels.
- `builder.add_conditional_edges(src, router_fn, path_map=None)` — `router_fn(state) -> str | list[str]`.
- `Command(goto=..., update={...}, graph=Command.PARENT)` — combine state update + routing in one return; `graph=Command.PARENT` routes across a subgraph boundary.
- `graph = builder.compile(checkpointer=None, store=None, interrupt_before=[], interrupt_after=[])`.

**Minimal (ReAct in raw form)**
```python
def llm_node(state: State) -> dict: ...
def tools_node(state: State) -> dict: ...

def route(state: State) -> str:
    last = state["messages"][-1]
    return "tools" if getattr(last, "tool_calls", None) else END

b = StateGraph(State)
b.add_node("llm", llm_node)
b.add_node("tools", tools_node)
b.add_edge(START, "llm")
b.add_conditional_edges("llm", route, {"tools": "tools", END: END})
b.add_edge("tools", "llm")
graph = b.compile()
```

**Command equivalent (node decides its own next hop)**
```python
def llm_node(state: State) -> Command:
    msg = model.invoke(state["messages"])
    nxt = "tools" if msg.tool_calls else END
    return Command(goto=nxt, update={"messages": [msg]})
```

**Trap.** No terminating edge → `GraphRecursionError` at step 25. Always have a path to `END`.

---

## Pillar 3 — Prebuilt Agent Loop (`create_agent`)

**API surface**
- `create_agent(model, tools, *, system_prompt=None, checkpointer=None, store=None, middleware=[], response_format=None)` → a compiled graph.
- `model`: a chat model instance or a string id (e.g. `"openai:gpt-4o"`).
- `tools`: list of `@tool`-decorated callables / `BaseTool` / `ToolNode`.
- `response_format`: a Pydantic model → structured final output (see Pillar 10).

**Minimal**
```python
from langchain.agents import create_agent
from langchain_core.tools import tool

@tool
def search(q: str) -> str:
    """Search the web."""
    ...

agent = create_agent("openai:gpt-4o", tools=[search], system_prompt="Be terse.")
result = agent.invoke({"messages": [{"role": "user", "content": "..."}]})
```

**Knobs that matter**
- Drop to raw `StateGraph` (Pillars 1–2) only when you need control `create_agent` doesn't expose; otherwise customize via `middleware=` (Pillar 8).
- `create_agent` *is* a LangGraph graph — it accepts `checkpointer`/`store` and streams identically.

**Trap.** Reaching for raw graphs to customize the loop when a single middleware would do it.

---

## Pillar 4 — Persistence: Checkpointers + Store

**Checkpointers (short-term / thread-scoped)** — `langgraph.checkpoint.*`
| Class | Module | Use |
|---|---|---|
| `InMemorySaver` | `langgraph.checkpoint.memory` | dev only |
| `SqliteSaver` / `AsyncSqliteSaver` | `langgraph.checkpoint.sqlite[.aio]` | local persistence |
| `PostgresSaver` / `AsyncPostgresSaver` | `langgraph.checkpoint.postgres[.aio]` | production standard |
| `MongoDBSaver` / `AsyncMongoDBSaver` | `langgraph.checkpoint.mongodb` | Mongo shops |
| Redis savers (+ `ShallowRedisSaver`, TTL) | `langgraph-checkpoint-redis` | TTL / latest-only |

```python
from langgraph.checkpoint.postgres import PostgresSaver

with PostgresSaver.from_conn_string(DB_URI) as cp:
    cp.setup()                                  # one-time: creates tables/indices
    graph = builder.compile(checkpointer=cp)
    graph.invoke(inputs, config={"configurable": {"thread_id": "user-42"}})
```

**Store (long-term / cross-thread)** — `langgraph.store.*`
- `BaseStore` interface; backends `InMemoryStore` (semantic search), `PostgresStore`, `MongoDBStore` (`langgraph-store-mongodb`, TTL), Redis store (vector).
- Namespaced by your keys, not `thread_id`. Injected as `runtime.store` inside nodes.

```python
from langgraph.store.postgres import PostgresStore
store.put(("user-42", "memories"), key="pref", value={"tone": "blunt"})
items = store.search(("user-42", "memories"), query="tone")
graph = builder.compile(checkpointer=cp, store=store)
```

**Knobs that matter**
- DB savers require `.setup()` once.
- Checkpointers store per-channel **deltas** keyed by version → don't re-serialize unchanged state. (Pillar 7/scale: `DeltaChannel`.)
- `config["configurable"]["thread_id"]` is mandatory for any checkpointed run.

**Trap.** `InMemorySaver` in prod (state dies on restart); confusing thread memory (checkpointer) with cross-session memory (Store).

---

# TIER 2 — RELIABILITY

## Pillar 5 — Human-in-the-Loop (`interrupt` / resume)

**API surface**
- `interrupt(payload)` — pauses, persists, surfaces `payload` to the caller. Requires a checkpointer.
- Resume: invoke again with `Command(resume=<value>)` on the same `thread_id`.
- Static gates: `compile(interrupt_before=[...], interrupt_after=[...])`.
- LC 1.0: `HumanInTheLoopMiddleware(interrupt_mode=..., when=predicate)`.

**Minimal**
```python
from langgraph.types import interrupt, Command

def approval(state: State) -> dict:
    decision = interrupt({"action": state["proposed_action"]})   # pauses here
    if decision != "approve":
        return {"messages": [{"role": "assistant", "content": "Cancelled."}]}
    return execute(state["proposed_action"])

# caller
graph.invoke(inputs, config=cfg)                 # raises/returns interrupt
graph.invoke(Command(resume="approve"), config=cfg)
```

**Knobs that matter**
- On resume, the **interrupted node re-runs from its top** (prior nodes don't). Side effects before `interrupt()` in the same node run twice → put them *after*, or make them idempotent.

**Trap.** Charging the card before the `interrupt()` call in the same node.

---

## Pillar 6 — Streaming + Observability

**Streaming** — `graph.stream(inputs, config, stream_mode=...)` / `.astream(...)`
| Mode | Emits | Use |
|---|---|---|
| `"updates"` | per-node state deltas | **default** for UIs (small) |
| `"values"` | full state each step | debugging (verbose) |
| `"messages"` | `(token_chunk, metadata)` | token streaming |
| `"custom"` | your events via `get_stream_writer()` | progress bars |
| `"debug"` / `"checkpoints"` / `"tasks"` | execution internals | deep debugging |
- Multiple modes: `stream_mode=["updates", "messages"]`.
- Typed streaming: `version="v2"` (unified `StreamPart`, `GraphOutput.value/.interrupts`); `version="v3"` (content-block events: `run.values` / `run.messages` / `run.lifecycle` / `run.subgraphs`) for new apps.

```python
from langgraph.config import get_stream_writer
def node(state):
    get_stream_writer()({"progress": 0.5})       # -> stream_mode="custom"
    ...
for chunk in graph.stream(inputs, cfg, stream_mode="updates"):
    print(chunk)
```

**Observability**
- LangSmith via env: `LANGSMITH_TRACING=true`, `LANGSMITH_API_KEY=...` (zero code). Waterfall + thread view + trace search.
- Vendor-neutral: LangGraph emits LangChain callbacks → OpenInference/OTel handlers (Langfuse, Arize Phoenix) if LangSmith is off-limits.

**Trap.** `stream_mode="values"` to the UI — resends growing state every step.

---

## Pillar 7 — Failure Handling

**API surface**
- `RetryPolicy(max_attempts=3, retry_on=..., backoff_factor=2.0, initial_interval=0.5, max_interval=..., jitter=True)` → `add_node(name, fn, retry_policy=...)`.
  - Default `retry_on` skips `ValueError`/`TypeError`/`ArithmeticError`/`ImportError`/`LookupError`/`NameError`/`AttributeError`; for `httpx`/`requests` retries on 5xx only.
- Per-node timeouts (v1.2, **async**): `add_node(..., timeout=TimeoutPolicy(run_timeout=..., idle_timeout=...))` → raises `NodeTimeoutError`, clears the failed attempt's writes.
- Per-node error handler (v1.2): `add_node(..., error_handler=fn)` where `fn(NodeError) -> Command` — runs after retries exhausted; **the Saga/compensation hook**.
- `recursion_limit` at invoke time; `GraphRecursionError` on overflow.
- Model failover: `model.with_fallbacks([cheaper_model])` (LangChain Runnable, distinct from node retries).

**Minimal**
```python
from langgraph.types import RetryPolicy
builder.add_node("call_api", call_api, retry_policy=RetryPolicy(max_attempts=4, backoff_factor=2.0))

def compensate(err) -> Command:          # error_handler, v1.2
    return Command(goto="rollback", update={"error": str(err)})
builder.add_node("charge", charge, error_handler=compensate)

graph.invoke(inputs, {"configurable": {"thread_id": "x"}, "recursion_limit": 50})
```

**Trap.** Bumping `recursion_limit` to silence `GraphRecursionError` instead of fixing the missing terminating edge.

---

# TIER 3 — HORIZON
*Signals + the specific class to reach for. Not needed for a first agent.*

## Pillar 8 — Context Engineering via Middleware

**Signal:** rising cost, context overflow, instruction drift on long threads.

**API surface** — `langchain.agents.middleware` (verify path), passed as `create_agent(..., middleware=[...])`. Hook points: `before_agent`, `before_model`, `wrap_model_call`, `wrap_tool_call`, `after_model`.

| Class | Does |
|---|---|
| `SummarizationMiddleware` | compress history near token limit / on `ContextOverflowError` |
| `LLMToolSelectorMiddleware` | fast model pre-selects relevant tools (cuts tool-schema bloat) |
| `PIIMiddleware` | redact PII pre-model |
| `ToolRetryMiddleware` / `ModelRetryMiddleware` | retry at tool/model granularity |
| `TodoListMiddleware` | scratchpad planning |

```python
from langchain.agents.middleware import SummarizationMiddleware, LLMToolSelectorMiddleware
agent = create_agent(model, tools, middleware=[
    SummarizationMiddleware(),
    LLMToolSelectorMiddleware(),
])
```
Higher-level: **Deep Agents** (`deepagents`, 0.6.x) bundles `FilesystemMiddleware`, `SubagentMiddleware` (context-isolated subagents), `SummarizationMiddleware`.

**Trap.** Adding summarization before traces (Pillar 6) prove you need it.

---

## Pillar 9 — Multi-Agent

**Signal:** one agent + too many tools/jobs misroutes.

**API surface**
- **Supervisor (recommended build):** parent `create_agent` whose "tools" are sub-agents (each itself a graph). Manual tool-calling supervisor is now preferred over the `langgraph-supervisor` package for context control.
- **Swarm / handoff:** nodes return `Command(goto="other_agent", graph=Command.PARENT)`; `langgraph-swarm` remembers last-active agent.
- Everything compiles to a graph → subgraphs nest (supervisor whose worker is a swarm).

```python
def supervisor(state) -> Command:
    target = route_llm(state)                      # "researcher" | "coder" | END
    return Command(goto=target)
# each worker: a compiled subgraph added as a node
```

**Trap.** Splitting before writing a routing-accuracy eval — you can't tell if it helped.

---

## Pillar 10 — Production: Eval, Structured Output, Deploy

**Signal:** real users; changes need regression safety.

**Structured output (do this from day one):**
```python
from pydantic import BaseModel
class Answer(BaseModel):
    verdict: str
    confidence: float
agent = create_agent(model, tools, response_format=Answer)   # deterministic assertions
```

**Eval:** LangSmith datasets + multi-turn evals; assert on the structured payload, not free text.

**Deploy / tooling**
- `langgraph dev` — local server (port 2024, hot reload) + Studio v2 (browser debugger: graph view, state inspection, rewind/edit/rerun).
- `langgraph build` → Docker image; `langgraph deploy` (Mar 2026) → cloud; K8s self-host via Helm + KEDA.
- Platform tiers: Cloud SaaS / Hybrid (SaaS control plane + self-hosted data plane) / Fully self-hosted in VPC. Server adds task queues, background runs, cron, webhooks, double-texting, durable execution.

**Trap.** Retrofitting `response_format` after you've built eval around free-text parsing.

---

## Scale addendum (when checkpoint writes hurt)
- **`DeltaChannel`** (v1.2, beta): stores per-step deltas instead of re-serializing accumulated state; `snapshot_frequency=K` writes a full snapshot every K steps to bound read latency. The lever for long-thread checkpoint bloat on Postgres/Mongo.
- **`Send` fan-out** (`from langgraph.types import Send`): return `[Send(node, substate), ...]` from a conditional edge for dynamic map-reduce. Keep payloads to IDs (each branch copies its state); cap with invoke-time `max_concurrency`; a superstep is atomic (one branch failing rolls back that superstep's writes, but checkpointed completed nodes don't re-run on resume).
- **Durability gap:** checkpoints save *between* nodes, not *inside* one — an in-node loop loses progress on crash, and there's no built-in distributed lock against two workers resuming one `thread_id`. For exactly-once across distributed workers, pair with a durable-execution engine (e.g. Temporal) or LangGraph Platform's managed queue.

---

## One-page API map

| # | Pillar | Import / call |
|---|---|---|
| 1 | State | `StateGraph(TypedDict)`, `Annotated[list, add_messages]`, `Overwrite` |
| 2 | Graph | `add_node/add_edge/add_conditional_edges`, `Command(goto, update)`, `START/END` |
| 3 | Loop | `create_agent(model, tools, ...)` |
| 4 | Persistence | `PostgresSaver`/`MongoDBSaver` + `thread_id`; `BaseStore`/`PostgresStore` |
| 5 | HITL | `interrupt(payload)` + `Command(resume=...)`; `HumanInTheLoopMiddleware` |
| 6 | Observe | `.stream(stream_mode="updates")`, `get_stream_writer()`, `LANGSMITH_TRACING` |
| 7 | Failure | `RetryPolicy`, `TimeoutPolicy`, `error_handler`, `recursion_limit`, `.with_fallbacks()` |
| 8 | Context | `create_agent(middleware=[SummarizationMiddleware(), ...])`; `deepagents` |
| 9 | Multi-agent | nested `create_agent` subgraphs; `Command(goto, graph=Command.PARENT)` |
| 10 | Production | `response_format=PydanticModel`, LangSmith eval, `langgraph dev/build/deploy` |
| ⤓ | Scale | `DeltaChannel(snapshot_frequency)`, `Send(...)` + `max_concurrency` |
