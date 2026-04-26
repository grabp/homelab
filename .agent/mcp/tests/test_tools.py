"""Tests for MCP server tools."""

import pytest
from pathlib import Path

from homelab_mcp.repo import get_repo_root, get_machine_ip, get_services


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
