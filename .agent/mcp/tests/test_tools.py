"""Tests for MCP server tools."""

import pytest
from pathlib import Path

from homelab_mcp.repo import get_repo_root, get_machine_ip, get_services, get_service_info, get_stages, get_pattern


def test_get_repo_root():
    """Test that we can find the repo root."""
    root = get_repo_root()
    assert root.exists()
    assert (root / "flake.nix").exists()


def test_get_machine_ip_pebble():
    """Test getting pebble IP from vars.nix."""
    ip = get_machine_ip("pebble")
    assert ip is not None
    assert ip == "192.168.10.50"


def test_get_machine_ip_vps():
    """Test getting VPS IP from vars.nix."""
    ip = get_machine_ip("vps")
    assert ip is not None
    assert ip == "204.168.181.110"


def test_get_machine_ip_invalid():
    """Test getting IP for non-existent machine."""
    ip = get_machine_ip("invalid")
    assert ip is None


def test_get_services():
    """Test getting list of homelab services."""
    services = get_services()
    assert isinstance(services, list)
    assert len(services) > 0
    assert "caddy" in services
    assert all(isinstance(s, str) for s in services)


def test_get_service_info_caddy():
    """Test getting service info for caddy."""
    info = get_service_info("caddy")
    assert info is not None
    assert "ports" in info
    assert "secrets" in info
    assert "patterns" in info

    # Caddy should have ports 80 and 443
    assert isinstance(info["ports"], list)
    assert 80 in info["ports"]
    assert 443 in info["ports"]

    # Caddy should have caddy/env secret
    assert isinstance(info["secrets"], list)
    assert "caddy/env" in info["secrets"]

    # Patterns should be a list
    assert isinstance(info["patterns"], list)


def test_get_service_info_home_assistant():
    """Test getting service info for home-assistant (has pattern references)."""
    info = get_service_info("home-assistant")
    assert info is not None

    # Home Assistant has pattern references (11, 14, 16)
    assert "patterns" in info
    assert isinstance(info["patterns"], list)
    # Should contain at least some pattern IDs
    assert len(info["patterns"]) > 0


def test_get_service_info_invalid():
    """Test getting service info for non-existent service."""
    info = get_service_info("nonexistent-service")
    assert info is None


def test_list_stages():
    """Test getting list of stages from PROGRESS.md."""
    stages = get_stages()
    assert isinstance(stages, list)
    assert len(stages) > 0

    # Verify structure of first stage
    first_stage = stages[0]
    assert "number" in first_stage
    assert "description" in first_stage
    assert "status" in first_stage
    assert "doc_link" in first_stage

    # Stage 1 should be in the list
    stage_numbers = [s["number"] for s in stages]
    assert "1" in stage_numbers

    # Find stage 1 and verify its properties
    stage_1 = next(s for s in stages if s["number"] == "1")
    assert stage_1["description"] == "Base System"
    assert "COMPLETE" in stage_1["status"]
    assert "docs/roadmap/stage-01-base-system.md" in stage_1["doc_link"]

    # Verify all stages have required fields
    for stage in stages:
        assert isinstance(stage["number"], str)
        assert isinstance(stage["description"], str)
        assert isinstance(stage["status"], str)
        assert isinstance(stage["doc_link"], str)


def test_get_pattern_by_id():
    """Test getting pattern by ID."""
    pattern = get_pattern("17")
    assert pattern is not None
    assert pattern["id"] == "17"
    assert pattern["name"] == "17-podman-volume-uid"
    assert "title" in pattern
    assert "Pattern 17" in pattern["title"]
    assert "tags" in pattern
    assert "podman" in pattern["tags"]
    assert "content" in pattern
    assert "SQLite WAL" in pattern["content"]
    assert pattern["file"] == "docs/patterns/17-podman-volume-uid.md"


def test_get_pattern_by_tag():
    """Test getting pattern by tag (returns first match)."""
    pattern = get_pattern("podman")
    assert pattern is not None
    # Should return pattern 17 (first podman match in index)
    assert pattern["id"] == "17"
    assert "podman" in pattern["tags"]


def test_get_pattern_invalid():
    """Test getting non-existent pattern."""
    pattern = get_pattern("999")
    assert pattern is None

    pattern = get_pattern("nonexistent-tag")
    assert pattern is None
