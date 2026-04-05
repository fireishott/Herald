"""MCP endpoint for voice mode tool delegation.

Exposes a single ``hermes_delegate`` tool that OpenAI's Realtime API can call
server-side during a voice session.  The tool proxies the request through the
relay to the user's connected Hermes host.

The implementation uses FastMCP with a proper ASGI lifespan so the internal
task group is initialised before any HTTP requests arrive.
"""

from __future__ import annotations

import asyncio
import contextvars
import logging
from contextlib import asynccontextmanager
from dataclasses import dataclass
from urllib.parse import parse_qs

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from mcp.server.fastmcp import FastMCP
from starlette.applications import Starlette

from .services import get_voice_session_for_tool_token, record_voice_turn

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class TalkMCPContext:
    voice_session_id: str
    user_id: str
    host_id: str


_current_context: contextvars.ContextVar[TalkMCPContext | None] = contextvars.ContextVar(
    "hermes_mobile_talk_mcp_context",
    default=None,
)


def build_talk_mcp_app(relay_app: FastAPI):
    mcp = FastMCP(
        "hermes-mobile-talk",
        instructions="Relay-hosted bridge for Hermes Mobile talk mode.",
        stateless_http=True,
    )

    @mcp.tool(description="Delegate a voice request to the connected Hermes host.")
    async def hermes_delegate(prompt: str) -> str:
        context = _current_context.get()
        if context is None:
            raise RuntimeError("Talk session context is unavailable.")

        with relay_app.state.database.session() as db:
            record_voice_turn(
                db,
                voice_session_id=context.voice_session_id,
                role="user",
                source="tool",
                text=prompt,
            )

        result = await relay_app.state.send_connector_rpc(
            context.user_id,
            method="talk.delegate",
            params={
                "voiceSessionId": context.voice_session_id,
                "prompt": prompt,
            },
            timeout_seconds=relay_app.state.settings.talk_delegate_timeout_seconds,
        )

        text = str(result.get("text") or "").strip()
        with relay_app.state.database.session() as db:
            record_voice_turn(
                db,
                voice_session_id=context.voice_session_id,
                role="assistant",
                source="tool",
                text=text or "Hermes returned an empty voice delegation result.",
            )
        return text

    # Get the raw Starlette app that FastMCP builds.
    inner_app = mcp.streamable_http_app()

    # We need to run the inner app's lifespan (which initialises the MCP task
    # group) inside our own wrapper.  Build a thin ASGI layer that:
    #   1. On lifespan startup — boots the inner app's lifespan.
    #   2. On HTTP requests — authenticates the token and rewrites the path.
    _inner_started = asyncio.Event()
    _shutdown_event = asyncio.Event()

    async def _run_inner_lifespan() -> None:
        """Simulate an ASGI lifespan for the inner app."""
        startup_complete = asyncio.Event()
        shutdown_triggered = asyncio.Event()

        async def receive():
            if not startup_complete.is_set():
                startup_complete.set()
                return {"type": "lifespan.startup"}
            await shutdown_triggered.wait()
            return {"type": "lifespan.shutdown"}

        async def send(message):
            if message["type"] == "lifespan.startup.complete":
                _inner_started.set()
            elif message["type"] == "lifespan.shutdown.complete":
                pass

        scope = {"type": "lifespan", "asgi": {"version": "3.0"}}
        task = asyncio.create_task(inner_app(scope, receive, send))

        # Wait until the inner app signals startup complete.
        await _inner_started.wait()

        # Keep running until our own shutdown is requested.
        await _shutdown_event.wait()
        shutdown_triggered.set()
        await task

    _lifespan_task: asyncio.Task | None = None

    async def protected_app(scope, receive, send) -> None:
        nonlocal _lifespan_task

        if scope["type"] == "lifespan":
            # Boot the inner app's lifespan on first lifespan event.
            _lifespan_task = asyncio.create_task(_run_inner_lifespan())
            # Forward our own lifespan to stay alive.
            while True:
                message = await receive()
                if message["type"] == "lifespan.startup":
                    await _inner_started.wait()
                    await send({"type": "lifespan.startup.complete"})
                elif message["type"] == "lifespan.shutdown":
                    _shutdown_event.set()
                    if _lifespan_task:
                        await _lifespan_task
                    await send({"type": "lifespan.shutdown.complete"})
                    return
            return

        if scope["type"] != "http":
            await inner_app(scope, receive, send)
            return

        # Ensure the inner app's task group is ready.
        if not _inner_started.is_set():
            if _lifespan_task is None:
                _lifespan_task = asyncio.create_task(_run_inner_lifespan())
            await asyncio.wait_for(_inner_started.wait(), timeout=10.0)

        # Authenticate via query-string token.
        token_values = parse_qs(scope.get("query_string", b"").decode("utf-8")).get("token", [])
        relay_tool_token = token_values[0] if token_values else None
        if not relay_tool_token:
            await JSONResponse({"error": "Missing talk tool token."}, status_code=401)(scope, receive, send)
            return

        with relay_app.state.database.session() as db:
            voice_session = get_voice_session_for_tool_token(db, relay_tool_token=relay_tool_token)
        if voice_session is None:
            await JSONResponse({"error": "Invalid or expired talk tool token."}, status_code=401)(scope, receive, send)
            return

        token = _current_context.set(
            TalkMCPContext(
                voice_session_id=voice_session.id,
                user_id=voice_session.user_id,
                host_id=voice_session.host_id,
            )
        )
        try:
            # Rewrite path to /mcp so the inner FastMCP route matches.
            scope = dict(scope, path="/mcp")
            await inner_app(scope, receive, send)
        finally:
            _current_context.reset(token)

    return protected_app
