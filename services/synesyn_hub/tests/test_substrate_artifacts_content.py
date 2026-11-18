from __future__ import annotations

import asyncio
import base64
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

HERE = Path(__file__).resolve()
HUB_ROOT = HERE.parents[1]
if str(HUB_ROOT) not in sys.path:
	sys.path.insert(0, str(HUB_ROOT))

from app.auth import install_auth
from app.config import WorkspaceConfig
from app.substrate.db import Substrate
from app.substrate.repo import SubstrateRepo
from app.substrate.routes import router as substrate_router


def _make_workspace(root: Path) -> WorkspaceConfig:
	root.mkdir(parents=True, exist_ok=True)
	artifacts = root / "artifacts"
	substrate = root / "substrate"
	exports = root / "exports"
	logs = root / "logs"
	for d in (artifacts, substrate, exports, logs):
		d.mkdir(parents=True, exist_ok=True)
	return WorkspaceConfig(
		name="Test Workspace",
		slug="test-workspace",
		root=root,
		substrate_dir=substrate,
		artifacts_dir=artifacts,
		exports_dir=exports,
		logs_dir=logs,
	)


class _HubApp:
	def __init__(self, workspace: WorkspaceConfig, *, auth_enabled: bool = False, auth_token: str = ""):
		self.workspace = workspace
		self.substrate = Substrate(workspace.substrate_dir / "substrate.sqlite")
		asyncio.run(self.substrate.open())
		self.repo = SubstrateRepo(self.substrate, enforce_provenance=False)
		self.app = FastAPI()
		self.app.state.cfg = SimpleNamespace(
			workspace=workspace,
			enforce_provenance=False,
			auth_enabled=auth_enabled,
			auth_token=auth_token,
		)
		self.app.state.substrate = self.substrate
		self.app.state.substrate_repo = self.repo
		self.app.include_router(substrate_router, prefix="/substrate")
		if auth_enabled:
			install_auth(self.app, SimpleNamespace(auth_enabled=True, auth_token=auth_token))
		self.client = TestClient(self.app)

	def close(self) -> None:
		asyncio.run(self.substrate.close())


@pytest.fixture
def hub(tmp_path: Path):
	h = _HubApp(_make_workspace(tmp_path / "ws"))
	try:
		yield h
	finally:
		h.close()


def test_get_artifact_content_success(hub: _HubApp) -> None:
	png_bytes = (
		b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01"
		b"\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00"
		b"\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05"
		b"\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82"
	)
	payload = {
		"artifact_type": "image.generated",
		"inline_bytes_base64": base64.b64encode(png_bytes).decode("ascii"),
		"ext": "png",
		"metadata": {"provenance": {"generated_by": "test.fixture"}},
	}
	created = hub.client.post("/substrate/artifacts", json=payload)
	assert created.status_code == 200
	art_id = created.json()["id"]

	resp = hub.client.get(f"/substrate/artifacts/{art_id}/content")
	assert resp.status_code == 200
	assert resp.content == png_bytes
	assert "image/png" in (resp.headers.get("content-type") or "")


def test_get_artifact_content_missing(hub: _HubApp) -> None:
	resp = hub.client.get("/substrate/artifacts/art_does_not_exist/content")
	assert resp.status_code == 404


def test_get_artifact_content_auth_off_allows_anonymous(hub: _HubApp) -> None:
	payload = {
		"artifact_type": "image.generated",
		"inline_bytes_base64": base64.b64encode(b"abc").decode("ascii"),
		"ext": "bin",
		"metadata": {"provenance": {"generated_by": "test.fixture"}},
	}
	art_id = hub.client.post("/substrate/artifacts", json=payload).json()["id"]
	resp = hub.client.get(f"/substrate/artifacts/{art_id}/content")
	assert resp.status_code == 200
	assert resp.content == b"abc"


def test_get_artifact_content_auth_on_requires_bearer(tmp_path: Path) -> None:
	h = _HubApp(_make_workspace(tmp_path / "ws-auth"), auth_enabled=True, auth_token="secret-token")
	try:
		# Missing bearer → 401
		missing = h.client.get("/substrate/artifacts/art_x/content")
		assert missing.status_code == 401
		assert missing.json().get("error") == "missing_bearer_token"

		# Wrong bearer → 403
		wrong = h.client.get(
			"/substrate/artifacts/art_x/content",
			headers={"Authorization": "Bearer wrong"},
		)
		assert wrong.status_code == 403
		assert wrong.json().get("error") == "invalid_token"

		# Create + fetch with correct bearer
		headers = {"Authorization": "Bearer secret-token"}
		payload = {
			"artifact_type": "image.generated",
			"inline_bytes_base64": base64.b64encode(b"auth-ok").decode("ascii"),
			"ext": "bin",
			"metadata": {"provenance": {"generated_by": "test.fixture"}},
		}
		created = h.client.post("/substrate/artifacts", json=payload, headers=headers)
		assert created.status_code == 200
		art_id = created.json()["id"]
		ok = h.client.get(f"/substrate/artifacts/{art_id}/content", headers=headers)
		assert ok.status_code == 200
		assert ok.content == b"auth-ok"
	finally:
		h.close()


def test_get_artifact_content_rejects_path_outside_vault(hub: _HubApp) -> None:
	# Index a record whose URI points outside the artifacts vault.
	outside = Path(tempfile.gettempdir()) / "synesyn_outside_artifact.bin"
	outside.write_bytes(b"outside")
	art_id = asyncio.run(
		hub.repo.insert_artifact(
			{
				"id": "art_outside_vault",
				"artifact_type": "image.generated",
				"uri": outside.resolve().as_uri(),
				"hash": "deadbeef",
				"metadata": {"provenance": {"generated_by": "test.fixture"}},
			}
		)
	)
	asyncio.run(hub.repo.commit())
	resp = hub.client.get(f"/substrate/artifacts/{art_id}/content")
	assert resp.status_code == 404
	try:
		outside.unlink()
	except FileNotFoundError:
		pass
