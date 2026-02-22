from __future__ import annotations

from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]


def test_required_files_exist() -> None:
    required = [
        ROOT / "compose" / "docker-compose.yml",
        ROOT / "compose" / "docker-compose.pumba.yml",
        ROOT / "compose" / "docker-compose.keepalived.yml",
        ROOT / "scripts" / "evidence.sh",
        ROOT / "chaos" / "scripts" / "chaos-primary-kill.sh",
        ROOT / "pgbackrest" / "scripts" / "pitr-restore.sh",
        ROOT / "Makefile",
        ROOT / ".env.example",
    ]
    missing = [str(path) for path in required if not path.exists()]
    assert not missing, f"Arquivos ausentes: {missing}"


def test_compose_yaml_is_valid() -> None:
    compose_path = ROOT / "compose" / "docker-compose.yml"
    with compose_path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    assert "services" in data
    assert "pg1" in data["services"]
    assert "haproxy" in data["services"]


def test_run_id_contract_in_scripts() -> None:
    run_id_script = (ROOT / "scripts" / "lib" / "run_id.sh").read_text(encoding="utf-8")
    assert "date -u +%Y%m%dT%H%M%SZ" in run_id_script
