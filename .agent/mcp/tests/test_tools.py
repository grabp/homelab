"""Tests for MCP server tools."""

import pytest
from pathlib import Path

from homelab_mcp.repo import get_repo_root, get_machine_ip, get_services, get_service_info


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
