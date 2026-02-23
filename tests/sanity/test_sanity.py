from __future__ import annotations

import re
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[2]
CHAOS_DIR = ROOT / "chaos" / "scripts"
EXPECTED_CHAOS_SCRIPTS = [
    "chaos-primary-kill.sh",
    "chaos-etcd-quorum.sh",
    "chaos-primary-etcd-partition.sh",
    "chaos-replica-lag.sh",
    "chaos-archive-break.sh",
]
EXPECTED_CHAOS_TARGETS = [
    "chaos-primary-kill",
    "chaos-etcd-quorum",
    "chaos-primary-etcd-partition",
    "chaos-replica-lag",
    "chaos-archive-break",
]


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


def test_chaos_scripts_have_result_contract() -> None:
    for script_name in EXPECTED_CHAOS_SCRIPTS:
        script_path = CHAOS_DIR / script_name
        text = script_path.read_text(encoding="utf-8")
        assert "set -euo pipefail" in text, f"{script_name}: shell strict mode ausente"
        assert "result.json" in text, f"{script_name}: nao gera result.json"
        assert "exit 1" in text, f"{script_name}: nao falha explicitamente quando criterio quebra"


def test_makefile_has_chaos_targets() -> None:
    makefile = (ROOT / "Makefile").read_text(encoding="utf-8")
    for target in EXPECTED_CHAOS_TARGETS:
        assert re.search(rf"(?m)^{re.escape(target)}\s*:", makefile), f"Target ausente no Makefile: {target}"


def test_shell_scripts_use_strict_mode() -> None:
    script_paths = sorted((ROOT / "chaos" / "scripts").glob("*.sh"))
    script_paths += sorted((ROOT / "pgbackrest" / "scripts").glob("*.sh"))
    script_paths += sorted((ROOT / "scripts").glob("*.sh"))
    script_paths += sorted((ROOT / "scripts" / "lib").glob("*.sh"))

    for path in script_paths:
        text = path.read_text(encoding="utf-8")
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        assert lines[0] == "#!/usr/bin/env bash", f"{path}: shebang inesperado"
        assert "set -euo pipefail" in lines[:4], f"{path}: esperado set -euo pipefail no inicio"


def test_ci_workflow_runs_e2e() -> None:
    workflow = (ROOT / ".github" / "workflows" / "smoke.yml").read_text(encoding="utf-8")
    assert re.search(r"(?m)^  e2e:\s*$", workflow), "workflow smoke sem job e2e"
    assert "make up" in workflow and "make init" in workflow and "make test" in workflow
