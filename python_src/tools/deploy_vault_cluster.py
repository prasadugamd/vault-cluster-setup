from __future__ import annotations

from pathlib import Path
from typing import Any
import shlex

from .common import text_response, run_shell, ToolResponse


def deploy_vault_cluster(args: dict[str, Any]) -> ToolResponse:
    config_files = args.get("configFiles", [])
    deployment_type = args.get("deploymentType")
    skip_certificates = bool(args.get("skipCertificates", False))
    skip_prerequisites = bool(args.get("skipPrerequisites", False))
    working_directory = args.get("workingDirectory") or str(Path.cwd())

    try:
        config_file_paths = [str(Path(working_directory) / f) for f in config_files]

        command = f"cd {shlex.quote(working_directory)} && ./setup-vault-cluster.sh"
        for config_path in config_file_paths:
            command += f" {shlex.quote(Path(config_path).name)}"

        if skip_certificates:
            command += " --skip-certificates"
        if skip_prerequisites:
            command += " --skip-prerequisites"

        stdout, stderr = run_shell(command, cwd=working_directory, max_bytes=10 * 1024 * 1024)

        response = "# Vault Cluster Deployment\n\n"
        response += f"**Deployment Type:** {deployment_type}\n"
        response += f"**Configuration Files:** {', '.join(config_files)}\n\n"
        response += f"## Deployment Output\n\n```\n{stdout}```\n"

        if stderr:
            response += f"\n## Warnings/Errors\n\n```\n{stderr}```\n"

        response += "\n## Next Steps\n\n"
        if deployment_type in ("unsealer-only", "complete"):
            response += "1. Initialize the unsealer vault: Use `initialize_vault` tool\n"
            response += "2. Enable transit secrets engine\n"
        if deployment_type in ("data-vault", "complete"):
            response += "3. Verify data vault auto-unsealed\n"
            response += "4. Check cluster status with `check_cluster_status` tool\n"

        return text_response(response)
    except Exception as error:  # noqa: BLE001
        return text_response(
            f"Deployment failed: {error}\n\nUse the troubleshoot_deployment tool to diagnose issues.",
            is_error=True,
        )
