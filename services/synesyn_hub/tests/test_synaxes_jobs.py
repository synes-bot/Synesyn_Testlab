"""Contract/shape tests for synaxes.* Hub jobs (not embedding quality)."""

from __future__ import annotations

import asyncio
import sys
import tempfile
from pathlib import Path
from types import SimpleNamespace

from fastapi import FastAPI

HERE = Path(__file__).resolve()
HUB_ROOT = HERE.parents[1]
if str(HUB_ROOT) not in sys.path:
	sys.path.insert(0, str(HUB_ROOT))

from app.config import WorkspaceConfig
from app.events import EventBus
from app.routes.jobs import run_job
from app.substrate.db import Substrate
from app.substrate.repo import SubstrateRepo


def _make_workspace(root: Path) -> WorkspaceConfig:
	root.mkdir(parents=True, exist_ok=True)
	artifacts = root / "artifacts"
	artifacts.mkdir(parents=True, exist_ok=True)
	return WorkspaceConfig(
		name="SynAxes Jobs Test",
		slug="synaxes-jobs-test",
		root=root,
		substrate_dir=root / "substrate",
		artifacts_dir=artifacts,
		exports_dir=root / "exports",
		logs_dir=root / "logs",
	)


class _JobHarness:
	def __init__(self) -> None:
		self.tmp = tempfile.TemporaryDirectory()
		self.base = Path(self.tmp.name)
		self.workspace = _make_workspace(self.base / "workspace")
		self.substrate = Substrate(self.workspace.substrate_dir / "substrate.sqlite")
		self.repo: SubstrateRepo | None = None
		self.app: FastAPI | None = None

	async def setup(self) -> None:
		await self.substrate.open()
		self.repo = SubstrateRepo(self.substrate, enforce_provenance=False)
		self.app = FastAPI()
		self.app.state.cfg = SimpleNamespace(workspace=self.workspace, enforce_provenance=False)
		self.app.state.substrate_repo = self.repo
		self.app.state.event_bus = EventBus(ring_buffer_size=64)

	async def teardown(self) -> None:
		await self.substrate.close()
		self.tmp.cleanup()

	async def run(self, job_type: str, payload: dict) -> dict:
		assert self.repo is not None and self.app is not None
		job_id = await self.repo.create_job(
			{
				"job_type": job_type,
				"status": "queued",
				"input": {"input": payload, "output_target": {}, "metadata": {}},
				"metadata": {},
			}
		)
		await self.repo.commit()
		await run_job(job_id, self.app)
		job = await self.repo.get_job(job_id)
		assert job is not None
		return job


def _assert_completed_with_artifact(job: dict, *, output_key: str, artifact_type: str) -> str:
	assert job["status"] == "completed", job.get("error")
	assert not job.get("error")
	output = job.get("output_json") or {}
	assert isinstance(output, dict)
	artifact_id = str(output.get(output_key) or "").strip()
	assert artifact_id, f"missing {output_key} in {output}"
	artifacts = job.get("artifacts_json") or []
	assert isinstance(artifacts, list) and artifacts
	first = artifacts[0]
	assert first.get("artifact_id") == artifact_id
	assert first.get("artifact_type") == artifact_type
	assert str(first.get("uri") or "").strip()
	return artifact_id


def _run_job_case(job_type: str, payload: dict, *, output_key: str, artifact_type: str) -> None:
	async def _body() -> None:
		harness = _JobHarness()
		await harness.setup()
		try:
			job = await harness.run(job_type, payload)
			_assert_completed_with_artifact(job, output_key=output_key, artifact_type=artifact_type)
		finally:
			await harness.teardown()

	asyncio.run(_body())


def test_synaxes_embed_text_contract() -> None:
	_run_job_case(
		"synaxes.embed_text",
		{"item_ids": ["a", "b"], "texts": ["alpha theme", "beta theme"], "dim": 32},
		output_key="embeddings_artifact_id",
		artifact_type="embeddings.text",
	)


def test_synaxes_embed_image_contract() -> None:
	_run_job_case(
		"synaxes.embed_image",
		{"item_ids": ["img1", "img2"], "image_refs": ["hash:one", "hash:two"], "dim": 32},
		output_key="embeddings_artifact_id",
		artifact_type="embeddings.image",
	)


def test_synaxes_project_contract() -> None:
	vectors = [
		[1.0, 0.0, 0.0, 0.1],
		[0.0, 1.0, 0.0, 0.2],
		[0.0, 0.0, 1.0, 0.3],
		[1.0, 1.0, 0.0, 0.4],
	]
	_run_job_case(
		"synaxes.project",
		{"item_ids": ["i1", "i2", "i3", "i4"], "vectors": vectors, "dim": 3, "method": "pca"},
		output_key="projection_artifact_id",
		artifact_type="coords.projection_3d",
	)


def test_synaxes_cluster_contract() -> None:
	coords = {
		"i1": [0.0, 0.0, 0.0],
		"i2": [0.1, 0.0, 0.0],
		"i3": [5.0, 5.0, 0.0],
		"i4": [5.1, 5.0, 0.0],
	}
	_run_job_case(
		"synaxes.cluster",
		{"coords": coords, "k": 2, "seed": 7},
		output_key="cluster_artifact_id",
		artifact_type="graph.cluster_result",
	)


def test_synaxes_bridges_contract() -> None:
	coords = {
		"i1": [0.0, 0.0, 0.0],
		"i2": [0.2, 0.0, 0.0],
		"i3": [5.0, 0.0, 0.0],
		"i4": [5.2, 0.0, 0.0],
	}
	labels = {"i1": 0, "i2": 0, "i3": 1, "i4": 1}
	_run_job_case(
		"synaxes.bridges",
		{"coords": coords, "labels": labels},
		output_key="bridge_artifact_id",
		artifact_type="graph.bridge_result",
	)


def test_synaxes_hubs_contract() -> None:
	coords = {
		"i1": [0.0, 0.0, 0.0],
		"i2": [0.1, 0.0, 0.0],
		"i3": [0.0, 0.1, 0.0],
		"i4": [10.0, 10.0, 0.0],
	}
	_run_job_case(
		"synaxes.hubs",
		{"coords": coords, "k": 2},
		output_key="hub_artifact_id",
		artifact_type="graph.hub_result",
	)
