"""Comprehensive tests for Phase 5A Community DM 1-1 Audio & Video Call Signaling + Call Log."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict

import pytest
from bson import ObjectId
from fastapi import FastAPI
from fastapi.testclient import TestClient

from backend.app.database_community_dm import (
    COLL_DM_CONVERSATIONS,
    COLL_DM_MESSAGES,
    ensure_community_dm_indexes,
)
from backend.routers import community_dm
from backend.tests.test_community_dm_api import FakeDatabase, _make_token


@pytest.fixture()
def call_env(tmp_path, monkeypatch):
    fake_db = FakeDatabase()
    ensure_community_dm_indexes(fake_db)

    monkeypatch.setattr(community_dm, "db", fake_db)
    monkeypatch.setattr(community_dm, "COMMUNITY_DM_STATIC_DIR", str(tmp_path))
    monkeypatch.setattr(community_dm, "ws_manager", community_dm.DmConnectionManager())
    monkeypatch.setattr(community_dm, "call_registry", community_dm.DmCallRegistry())

    user_a_id = str(ObjectId())
    user_b_id = str(ObjectId())
    user_c_id = str(ObjectId())

    fake_db["users"].insert_one(
        {
            "_id": ObjectId(user_a_id),
            "email": "alice@saman.test",
            "password_hash": "super-secret-hash",
            "name": "Alice Athlete",
            "avatar_url": "/static/avatars/alice.jpg",
            "is_verified": True,
        }
    )
    fake_db["users"].insert_one(
        {
            "_id": ObjectId(user_b_id),
            "email": "bob@saman.test",
            "password_hash": "bob-secret-hash",
            "name": "Bob Coach",
            "avatar_url": "/static/avatars/bob.jpg",
            "is_verified": False,
        }
    )
    fake_db["users"].insert_one(
        {
            "_id": ObjectId(user_c_id),
            "email": "charlie@saman.test",
            "password_hash": "charlie-secret-hash",
            "name": "Charlie Runner",
            "avatar_url": None,
            "is_verified": False,
        }
    )

    app = FastAPI()
    app.include_router(community_dm.router)
    app.include_router(community_dm.ws_router)

    with TestClient(app) as client:
        token_a = _make_token(user_a_id, "alice@saman.test", "Alice Athlete")
        token_b = _make_token(user_b_id, "bob@saman.test", "Bob Coach")
        token_c = _make_token(user_c_id, "charlie@saman.test", "Charlie Runner")

        yield {
            "db": fake_db,
            "client": client,
            "a": {"id": user_a_id, "token": token_a, "headers": {"Authorization": f"Bearer {token_a}"}},
            "b": {"id": user_b_id, "token": token_b, "headers": {"Authorization": f"Bearer {token_b}"}},
            "c": {"id": user_c_id, "token": token_c, "headers": {"Authorization": f"Bearer {token_c}"}},
        }


def _create_conv(client: TestClient, sender: Dict[str, Any], target_id: str) -> str:
    resp = client.post(
        "/api/community/dm/conversations",
        headers=sender["headers"],
        json={"target_user_id": target_id},
    )
    assert resp.status_code == 200, resp.text
    return resp.json()["id"]


# ---------------------------------------------------------------------------
# 1. Security: Clients cannot forge call_log via REST POST /messages
# ---------------------------------------------------------------------------


def test_rest_cannot_spoof_call_log_message(call_env):
    client: TestClient = call_env["client"]
    a, b = call_env["a"], call_env["b"]
    conv_id = _create_conv(client, a, b["id"])

    resp = client.post(
        f"/api/community/dm/conversations/{conv_id}/messages",
        headers=a["headers"],
        json={"type": "call_log", "content": "Fake call log"},
    )
    assert resp.status_code == 422


# ---------------------------------------------------------------------------
# 2. Privacy & Block enforcement + Anti-IDOR / Anti-callee_id spoofing
# ---------------------------------------------------------------------------


def test_call_invite_enforces_blocks_who_can_dm_and_anti_spoofing(call_env):
    client: TestClient = call_env["client"]
    fake_db: FakeDatabase = call_env["db"]
    a, b, c = call_env["a"], call_env["b"], call_env["c"]

    conv_ab = _create_conv(client, a, b["id"])

    with client.websocket_connect(f"/api/community/ws/chat?token={a['token']}") as ws_a:
        with client.websocket_connect(f"/api/community/ws/chat?token={b['token']}") as ws_b:
            with client.websocket_connect(f"/api/community/ws/chat?token={c['token']}") as ws_c:
                # 2.1 Non-member C cannot invite on A-B conversation (anti-IDOR)
                ws_c.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-idor-1",
                        "conversation_id": conv_ab,
                        "call_type": "audio",
                    }
                )
                err_idor = ws_c.receive_json()
                assert err_idor["event"] == "call.error"
                assert err_idor["call_id"] == "call-idor-1"
                assert err_idor["code"] == "not_found"

                # 2.2 2-way block: B blocks A -> A gets call.error forbidden
                fake_db["community_blocks"].insert_one(
                    {"blocker_id": b["id"], "blocked_id": a["id"]}
                )
                ws_a.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-blocked-1",
                        "conversation_id": conv_ab,
                        "call_type": "audio",
                    }
                )
                err_blk = ws_a.receive_json()
                assert err_blk["event"] == "call.error"
                assert err_blk["call_id"] == "call-blocked-1"
                assert err_blk["code"] == "forbidden"
                assert fake_db[COLL_DM_MESSAGES].count_documents({"type": "call_log"}) == 0

                # Clear block
                fake_db["community_blocks"].docs.clear()

                # 2.3 who_can_dm = "nobody" -> forbidden
                fake_db["community_user_settings"].insert_one(
                    {"user_id": b["id"], "who_can_dm": "nobody"}
                )
                ws_a.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-nobody-1",
                        "conversation_id": conv_ab,
                        "call_type": "video",
                    }
                )
                err_nobody = ws_a.receive_json()
                assert err_nobody["event"] == "call.error"
                assert err_nobody["call_id"] == "call-nobody-1"
                assert err_nobody["code"] == "forbidden"

                # 2.4 who_can_dm = "followers" -> forbidden before follow, allowed after follow
                fake_db["community_user_settings"].update_one(
                    {"user_id": b["id"]}, {"$set": {"who_can_dm": "followers"}}
                )
                ws_a.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-followers-deny",
                        "conversation_id": conv_ab,
                        "call_type": "audio",
                    }
                )
                err_fol = ws_a.receive_json()
                assert err_fol["event"] == "call.error"
                assert err_fol["call_id"] == "call-followers-deny"
                assert err_fol["code"] == "forbidden"

                # Follow B -> invite succeeds, AND spoofed callee_id=C is ignored (rings B only)
                fake_db["community_follows"].insert_one(
                    {"follower_id": a["id"], "following_id": b["id"]}
                )
                ws_a.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-followers-ok",
                        "conversation_id": conv_ab,
                        "call_type": "audio",
                        "callee_id": c["id"],  # spoofed field must be ignored
                    }
                )
                invite_b = ws_b.receive_json()
                assert invite_b["event"] == "call.invite"
                assert invite_b["call_id"] == "call-followers-ok"
                assert invite_b["conversation_id"] == conv_ab
                assert invite_b["call_type"] == "audio"
                assert invite_b["caller"]["id"] == a["id"]
                assert invite_b["caller"]["name"] == "Alice Athlete"
                assert "email" not in invite_b["caller"]
                assert "password_hash" not in invite_b["caller"]

                # Verify C did not receive anything (ping -> immediate pong)
                ws_c.send_json({"event": "ping"})
                assert ws_c.receive_json() == {"event": "pong"}

                # Clean up active call via cancel
                ws_a.send_json({"event": "call.cancel", "call_id": "call-followers-ok"})
                assert ws_b.receive_json()["event"] == "call.cancel"
                assert ws_a.receive_json()["event"] == "message.created"
                assert ws_b.receive_json()["event"] == "message.created"


# ---------------------------------------------------------------------------
# 3. Full Audio & Video WebRTC Signaling Flow + call_log WS & REST check
# ---------------------------------------------------------------------------


def test_full_audio_and_video_call_flow_and_call_log_persistence(call_env):
    client: TestClient = call_env["client"]
    a, b, c = call_env["a"], call_env["b"], call_env["c"]
    conv_ab = _create_conv(client, a, b["id"])

    with client.websocket_connect(f"/api/community/ws/chat?token={a['token']}") as ws_a:
        with client.websocket_connect(f"/api/community/ws/chat?token={b['token']}") as ws_b:
            with client.websocket_connect(f"/api/community/ws/chat?token={c['token']}") as ws_c:
                # ---- AUDIO CALL ----
                ws_a.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "audio-call-001",
                        "conversation_id": conv_ab,
                        "call_type": "audio",
                    }
                )
                inv = ws_b.receive_json()
                assert inv["event"] == "call.invite"
                assert inv["call_id"] == "audio-call-001"
                assert inv["call_type"] == "audio"
                assert inv["caller"]["id"] == a["id"]

                # B accepts
                ws_b.send_json({"event": "call.accept", "call_id": "audio-call-001"})
                acc = ws_a.receive_json()
                assert acc == {
                    "event": "call.accept",
                    "call_id": "audio-call-001",
                    "conversation_id": conv_ab,
                    "by_user_id": b["id"],
                }

                # Unauthorized C cannot inject webrtc.offer or webrtc.ice into A-B call
                ws_c.send_json(
                    {
                        "event": "webrtc.offer",
                        "call_id": "audio-call-001",
                        "sdp": "v=0-evil",
                        "sdp_type": "offer",
                    }
                )
                err_c = ws_c.receive_json()
                assert err_c["event"] == "call.error"
                assert err_c["code"] == "forbidden"

                # A sends webrtc.offer -> B receives intact
                ws_a.send_json(
                    {
                        "event": "webrtc.offer",
                        "call_id": "audio-call-001",
                        "sdp": "v=0\r\no=alice-audio-offer",
                        "sdp_type": "offer",
                    }
                )
                offer_b = ws_b.receive_json()
                assert offer_b == {
                    "event": "webrtc.offer",
                    "call_id": "audio-call-001",
                    "conversation_id": conv_ab,
                    "from_user_id": a["id"],
                    "sdp": "v=0\r\no=alice-audio-offer",
                    "sdp_type": "offer",
                }

                # B sends webrtc.answer -> A receives intact
                ws_b.send_json(
                    {
                        "event": "webrtc.answer",
                        "call_id": "audio-call-001",
                        "sdp": "v=0\r\no=bob-audio-answer",
                        "sdp_type": "answer",
                    }
                )
                ans_a = ws_a.receive_json()
                assert ans_a == {
                    "event": "webrtc.answer",
                    "call_id": "audio-call-001",
                    "conversation_id": conv_ab,
                    "from_user_id": b["id"],
                    "sdp": "v=0\r\no=bob-audio-answer",
                    "sdp_type": "answer",
                }

                # A sends webrtc.ice (sdp_mline_index=0 preserved) -> B receives intact
                ws_a.send_json(
                    {
                        "event": "webrtc.ice",
                        "call_id": "audio-call-001",
                        "candidate": "candidate:1 1 UDP 2122252543 192.0.2.1 54400 typ host",
                        "sdp_mid": "0",
                        "sdp_mline_index": 0,
                    }
                )
                ice_b = ws_b.receive_json()
                assert ice_b == {
                    "event": "webrtc.ice",
                    "call_id": "audio-call-001",
                    "conversation_id": conv_ab,
                    "from_user_id": a["id"],
                    "candidate": "candidate:1 1 UDP 2122252543 192.0.2.1 54400 typ host",
                    "sdp_mid": "0",
                    "sdp_mline_index": 0,
                }

                # Backdate answered_at by 80 seconds to verify duration calculation & Vietnamese preview
                session = community_dm.call_registry.sessions["audio-call-001"]
                session.answered_at = datetime.now(timezone.utc) - timedelta(seconds=80)

                # A hangs up
                ws_a.send_json({"event": "call.hangup", "call_id": "audio-call-001"})
                hang_b = ws_b.receive_json()
                assert hang_b["event"] == "call.hangup"
                assert hang_b["call_id"] == "audio-call-001"
                assert hang_b["conversation_id"] == conv_ab
                assert hang_b["by_user_id"] == a["id"]
                assert hang_b["duration_sec"] >= 80

                # Both A and B receive message.created with call_log
                msg_evt_a = ws_a.receive_json()
                msg_evt_b = ws_b.receive_json()
                for evt in (msg_evt_a, msg_evt_b):
                    assert evt["event"] == "message.created"
                    assert evt["conversation_id"] == conv_ab
                    m = evt["message"]
                    assert m["type"] == "call_log"
                    assert m["sender_id"] == a["id"]
                    assert m["call_type"] == "audio"
                    assert m["call_status"] == "completed"
                    assert m["duration_sec"] >= 80
                    assert m["call_id"] == "audio-call-001"
                    assert m["content"].startswith("Cuộc gọi thoại • 01:2")

                # ---- VIDEO CALL ----
                ws_a.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "video-call-002",
                        "conversation_id": conv_ab,
                        "call_type": "video",
                    }
                )
                inv_v = ws_b.receive_json()
                assert inv_v["event"] == "call.invite"
                assert inv_v["call_type"] == "video"

                ws_b.send_json({"event": "call.accept", "call_id": "video-call-002"})
                assert ws_a.receive_json()["event"] == "call.accept"

                ws_b.send_json({"event": "call.hangup", "call_id": "video-call-002"})
                hang_a = ws_a.receive_json()
                assert hang_a["event"] == "call.hangup"
                assert hang_a["by_user_id"] == b["id"]

                vid_evt_a = ws_a.receive_json()
                vid_evt_b = ws_b.receive_json()
                assert vid_evt_a["message"]["call_type"] == "video"
                assert vid_evt_a["message"]["call_status"] == "completed"
                assert vid_evt_b["message"]["call_id"] == "video-call-002"

    # Verify REST GET /messages returns both call_logs with full fields
    r_msgs = client.get(f"/api/community/dm/conversations/{conv_ab}/messages", headers=a["headers"])
    assert r_msgs.status_code == 200
    items = r_msgs.json()["items"]
    assert len(items) == 2
    by_call_id = {item["call_id"]: item for item in items}
    assert by_call_id["audio-call-001"]["type"] == "call_log"
    assert by_call_id["audio-call-001"]["call_type"] == "audio"
    assert by_call_id["audio-call-001"]["call_status"] == "completed"
    assert by_call_id["audio-call-001"]["duration_sec"] >= 80
    assert by_call_id["video-call-002"]["call_type"] == "video"
    assert by_call_id["video-call-002"]["call_status"] == "completed"

    # Verify conversation inbox metadata updated
    r_convs = client.get("/api/community/dm/conversations", headers=a["headers"])
    assert r_convs.status_code == 200
    conv_item = r_convs.json()["items"][0]
    assert conv_item["last_message_type"] == "call_log"
    assert conv_item["last_message_preview"].startswith("Cuộc gọi video • ")


# ---------------------------------------------------------------------------
# 4. call.reject -> call_log("rejected") & call.cancel -> call_log("missed")
# ---------------------------------------------------------------------------


def test_call_reject_and_call_cancel_create_proper_call_logs(call_env):
    client: TestClient = call_env["client"]
    a, b = call_env["a"], call_env["b"]
    conv_ab = _create_conv(client, a, b["id"])

    with client.websocket_connect(f"/api/community/ws/chat?token={a['token']}") as ws_a:
        with client.websocket_connect(f"/api/community/ws/chat?token={b['token']}") as ws_b:
            # --- Reject flow ---
            ws_a.send_json(
                {
                    "event": "call.invite",
                    "call_id": "call-rej-1",
                    "conversation_id": conv_ab,
                    "call_type": "audio",
                }
            )
            assert ws_b.receive_json()["event"] == "call.invite"

            # Caller cannot call.reject
            ws_a.send_json({"event": "call.reject", "call_id": "call-rej-1"})
            assert ws_a.receive_json()["code"] == "forbidden"

            # Callee rejects
            ws_b.send_json({"event": "call.reject", "call_id": "call-rej-1"})
            rej_a = ws_a.receive_json()
            assert rej_a == {
                "event": "call.reject",
                "call_id": "call-rej-1",
                "conversation_id": conv_ab,
                "by_user_id": b["id"],
            }
            log_a = ws_a.receive_json()
            log_b = ws_b.receive_json()
            assert log_a["message"]["call_status"] == "rejected"
            assert log_a["message"]["duration_sec"] == 0
            assert log_a["message"]["content"] == "Đã từ chối cuộc gọi"
            assert log_b["message"]["call_id"] == "call-rej-1"

            # --- Cancel flow ---
            ws_a.send_json(
                {
                    "event": "call.invite",
                    "call_id": "call-can-1",
                    "conversation_id": conv_ab,
                    "call_type": "video",
                }
            )
            assert ws_b.receive_json()["event"] == "call.invite"

            # Callee cannot call.cancel
            ws_b.send_json({"event": "call.cancel", "call_id": "call-can-1"})
            assert ws_b.receive_json()["code"] == "forbidden"

            # Caller cancels
            ws_a.send_json({"event": "call.cancel", "call_id": "call-can-1"})
            can_b = ws_b.receive_json()
            assert can_b == {
                "event": "call.cancel",
                "call_id": "call-can-1",
                "conversation_id": conv_ab,
                "by_user_id": a["id"],
            }
            miss_a = ws_a.receive_json()
            miss_b = ws_b.receive_json()
            assert miss_a["message"]["call_status"] == "missed"
            assert miss_a["message"]["call_type"] == "video"
            assert miss_a["message"]["duration_sec"] == 0
            assert miss_a["message"]["content"] == "Cuộc gọi video nhỡ"
            assert miss_b["message"]["call_id"] == "call-can-1"

    # Unread count incremented for callee B due to missed call
    r_unread = client.get("/api/community/dm/unread-count", headers=b["headers"])
    assert r_unread.json()["unread_count"] == 1


# ---------------------------------------------------------------------------
# 5. call.busy (auto busy when in another call + explicit callee busy)
# ---------------------------------------------------------------------------


def test_call_busy_auto_and_explicit(call_env):
    client: TestClient = call_env["client"]
    a, b, c = call_env["a"], call_env["b"], call_env["c"]
    conv_ab = _create_conv(client, a, b["id"])
    conv_cb = _create_conv(client, c, b["id"])
    conv_ac = _create_conv(client, a, c["id"])

    with client.websocket_connect(f"/api/community/ws/chat?token={a['token']}") as ws_a:
        with client.websocket_connect(f"/api/community/ws/chat?token={b['token']}") as ws_b:
            with client.websocket_connect(f"/api/community/ws/chat?token={c['token']}") as ws_c:
                # Start active call A <-> B
                ws_a.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-ab-active",
                        "conversation_id": conv_ab,
                        "call_type": "audio",
                    }
                )
                assert ws_b.receive_json()["event"] == "call.invite"
                ws_b.send_json({"event": "call.accept", "call_id": "call-ab-active"})
                assert ws_a.receive_json()["event"] == "call.accept"

                # C calls busy B -> C receives call.busy + missed call_log persisted
                ws_c.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-cb-busy",
                        "conversation_id": conv_cb,
                        "call_type": "video",
                    }
                )
                busy_c = ws_c.receive_json()
                assert busy_c == {
                    "event": "call.busy",
                    "call_id": "call-cb-busy",
                    "conversation_id": conv_cb,
                    "by_user_id": b["id"],
                }
                missed_c = ws_c.receive_json()
                missed_b = ws_b.receive_json()
                assert missed_c["event"] == "message.created"
                assert missed_c["message"]["call_status"] == "missed"
                assert missed_c["message"]["call_id"] == "call-cb-busy"
                assert missed_b["event"] == "message.created"
                assert missed_b["message"]["call_id"] == "call-cb-busy"

                # Busy caller A tries to call free C -> A receives call.busy, no missed log for A-C
                ws_a.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-ac-caller-busy",
                        "conversation_id": conv_ac,
                        "call_type": "audio",
                    }
                )
                busy_a = ws_a.receive_json()
                assert busy_a["event"] == "call.busy"
                assert busy_a["call_id"] == "call-ac-caller-busy"
                assert busy_a["conversation_id"] == conv_ac

                # End A <-> B call
                ws_a.send_json({"event": "call.hangup", "call_id": "call-ab-active"})
                assert ws_b.receive_json()["event"] == "call.hangup"
                assert ws_a.receive_json()["event"] == "message.created"
                assert ws_b.receive_json()["event"] == "message.created"

                # Explicit callee call.busy (e.g., OS phone call): C invites B -> B sends call.busy
                ws_c.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-cb-os-busy",
                        "conversation_id": conv_cb,
                        "call_type": "audio",
                    }
                )
                assert ws_b.receive_json()["event"] == "call.invite"

                ws_b.send_json({"event": "call.busy", "call_id": "call-cb-os-busy"})
                os_busy_c = ws_c.receive_json()
                assert os_busy_c == {
                    "event": "call.busy",
                    "call_id": "call-cb-os-busy",
                    "conversation_id": conv_cb,
                    "by_user_id": b["id"],
                }
                os_log_c = ws_c.receive_json()
                os_log_b = ws_b.receive_json()
                assert os_log_c["message"]["call_status"] == "missed"
                assert os_log_b["message"]["call_id"] == "call-cb-os-busy"


# ---------------------------------------------------------------------------
# 6. Multi-socket callee: call.handled_elsewhere & non-last disconnect safety
# ---------------------------------------------------------------------------


def test_multi_socket_accept_and_non_last_disconnect(call_env):
    client: TestClient = call_env["client"]
    a, b = call_env["a"], call_env["b"]
    conv_ab = _create_conv(client, a, b["id"])

    with client.websocket_connect(f"/api/community/ws/chat?token={a['token']}") as ws_a:
        with client.websocket_connect(f"/api/community/ws/chat?token={b['token']}") as ws_b1:
            with client.websocket_connect(f"/api/community/ws/chat?token={b['token']}") as ws_b2:
                ws_a.send_json(
                    {
                        "event": "call.invite",
                        "call_id": "call-multi-1",
                        "conversation_id": conv_ab,
                        "call_type": "audio",
                    }
                )
                assert ws_b1.receive_json()["event"] == "call.invite"
                assert ws_b2.receive_json()["event"] == "call.invite"

                # B accepts on device 1 -> A gets call.accept, device 2 gets call.handled_elsewhere
                ws_b1.send_json({"event": "call.accept", "call_id": "call-multi-1"})
                assert ws_a.receive_json()["event"] == "call.accept"
                handled = ws_b2.receive_json()
                assert handled == {
                    "event": "call.handled_elsewhere",
                    "call_id": "call-multi-1",
                    "conversation_id": conv_ab,
                }

            # ws_b2 closed, but ws_b1 is still open -> call must remain active
            assert "call-multi-1" in community_dm.call_registry.sessions
            ws_b1.send_json({"event": "call.hangup", "call_id": "call-multi-1"})
            assert ws_a.receive_json()["event"] == "call.hangup"
            assert ws_a.receive_json()["event"] == "message.created"
            assert ws_b1.receive_json()["event"] == "message.created"


# ---------------------------------------------------------------------------
# 7. Disconnect cleanup (ringing + accepted) & call_log idempotency
# ---------------------------------------------------------------------------


def test_disconnect_cleanup_ringing_and_accepted(call_env):
    client: TestClient = call_env["client"]
    fake_db: FakeDatabase = call_env["db"]
    a, b = call_env["a"], call_env["b"]
    conv_ab = _create_conv(client, a, b["id"])

    # 7.1 Caller disconnects while ringing -> peer gets call.cancel + missed call_log
    with client.websocket_connect(f"/api/community/ws/chat?token={b['token']}") as ws_b:
        with client.websocket_connect(f"/api/community/ws/chat?token={a['token']}") as ws_a:
            ws_a.send_json(
                {
                    "event": "call.invite",
                    "call_id": "call-drop-ring",
                    "conversation_id": conv_ab,
                    "call_type": "audio",
                }
            )
            assert ws_b.receive_json()["event"] == "call.invite"
        # ws_a just disconnected
        cancel_evt = ws_b.receive_json()
        assert cancel_evt == {
            "event": "call.cancel",
            "call_id": "call-drop-ring",
            "conversation_id": conv_ab,
            "by_user_id": a["id"],
        }
        msg_evt = ws_b.receive_json()
        assert msg_evt["event"] == "message.created"
        assert msg_evt["message"]["call_status"] == "missed"
        assert msg_evt["message"]["call_id"] == "call-drop-ring"
        assert community_dm.call_registry.sessions == {}
        assert community_dm.call_registry.user_active_call == {}

    # 7.2 Callee disconnects after accepting -> peer gets call.hangup + completed call_log
    with client.websocket_connect(f"/api/community/ws/chat?token={a['token']}") as ws_a:
        with client.websocket_connect(f"/api/community/ws/chat?token={b['token']}") as ws_b:
            ws_a.send_json(
                {
                    "event": "call.invite",
                    "call_id": "call-drop-accepted",
                    "conversation_id": conv_ab,
                    "call_type": "video",
                }
            )
            assert ws_b.receive_json()["event"] == "call.invite"
            ws_b.send_json({"event": "call.accept", "call_id": "call-drop-accepted"})
            assert ws_a.receive_json()["event"] == "call.accept"
        # ws_b just disconnected
        hang_evt = ws_a.receive_json()
        assert hang_evt["event"] == "call.hangup"
        assert hang_evt["call_id"] == "call-drop-accepted"
        assert hang_evt["by_user_id"] == b["id"]
        msg_evt = ws_a.receive_json()
        assert msg_evt["event"] == "message.created"
        assert msg_evt["message"]["call_status"] == "completed"
        assert msg_evt["message"]["call_id"] == "call-drop-accepted"
        assert community_dm.call_registry.sessions == {}
        assert community_dm.call_registry.user_active_call == {}

    # 7.3 Verify _persist_call_log_sync idempotency (calling twice writes only 1 document)
    dup_session = community_dm.CallSession(
        call_id="call-idempotent-check",
        conversation_id=conv_ab,
        caller_id=a["id"],
        callee_id=b["id"],
        call_type="audio",
        state="ended",
        logged=True,
    )
    m1 = community_dm._persist_call_log_sync(fake_db, dup_session, "completed", 45)
    m2 = community_dm._persist_call_log_sync(fake_db, dup_session, "completed", 45)
    assert m1 is not None and m2 is not None
    assert m1.id == m2.id
    assert (
        fake_db[COLL_DM_MESSAGES].count_documents({"call_id": "call-idempotent-check"}) == 1
    )
    conv_doc = fake_db[COLL_DM_CONVERSATIONS].find_one({"_id": ObjectId(conv_ab)})
    assert conv_doc["last_message_type"] == "call_log"
    assert conv_doc["last_message_preview"] == "Cuộc gọi thoại • 00:45"
