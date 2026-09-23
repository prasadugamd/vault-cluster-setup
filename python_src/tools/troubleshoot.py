from __future__ import annotations

import json
from typing import Any

from .common import run_command, text_response, ToolResponse, require_ident


def troubleshoot_deployment(args: dict[str, Any]) -> ToolResponse:
    release_name = args.get("releaseName")
    check_type = args.get("checkType", "all")
    pod_name = args.get("podName")

    try:
        namespace = require_ident(args.get("namespace"), "namespace")
        if release_name:
            release_name = require_ident(release_name, "releaseName")
        if pod_name:
            pod_name = require_ident(pod_name, "podName")

        response = f"# Troubleshooting: {namespace}\n\n"

        if check_type in ("all", "pods"):
            response += _check_pods(namespace, release_name)

        if check_type in ("all", "logs"):
            if pod_name:
                response += _get_pod_logs(namespace, pod_name)
            elif release_name:
                response += _get_pod_logs(namespace, f"{release_name}-0")

        if check_type in ("all", "helm") and release_name:
            response += _check_helm_release(namespace, release_name)

        if check_type in ("all", "route") and release_name:
            response += _check_route(namespace, release_name)

        if check_type == "vault-status" and release_name:
            response += _check_vault_status(namespace, release_name)

        response += "\n## Remediation Suggestions\n\n"
        response += _generate_remediation_suggestions(namespace)

        return text_response(response)
    except Exception as error:  # noqa: BLE001
        return text_response(f"Troubleshooting failed: {error}", is_error=True)


def _check_pods(namespace: str, release_name: str | None) -> str:
    command = ["oc", "get", "pods", "-n", namespace]
    if release_name:
        command.extend(["-l", f"app.kubernetes.io/instance={release_name}"])
    command.append("-o")
    command.append("wide")

    try:
        stdout, _ = run_command(command)
        return f"## Pod Status\n\n```\n{stdout}```\n\n"
    except Exception:  # noqa: BLE001
        return "## Pod Status\n\nUnable to retrieve pod status\n\n"


def _get_pod_logs(namespace: str, pod_name: str) -> str:
    try:
        stdout, _ = run_command(["oc", "logs", "-n", namespace, pod_name, "--tail=100"])
        return f"## Pod Logs: {pod_name}\n\n```\n{stdout}```\n\n"
    except Exception:  # noqa: BLE001
        return f"## Pod Logs: {pod_name}\n\nUnable to retrieve logs\n\n"


def _check_helm_release(namespace: str, release_name: str) -> str:
    try:
        stdout, _ = run_command(["helm", "status", release_name, "-n", namespace])
        return f"## Helm Release Status\n\n```\n{stdout}```\n\n"
    except Exception:  # noqa: BLE001
        return "## Helm Release Status\n\nRelease not found or error occurred\n\n"


def _check_route(namespace: str, release_name: str) -> str:
    try:
        stdout, _ = run_command(["oc", "get", "route", "-n", namespace, f"{release_name}-route", "-o", "wide"])
        return f"## Route Status\n\n```\n{stdout}```\n\n"
    except Exception:  # noqa: BLE001
        return "## Route Status\n\nRoute not found\n\n"


def _check_vault_status(namespace: str, release_name: str) -> str:
    pod_name = f"{release_name}-0"
    try:
        stdout, _ = run_command(["oc", "exec", "-n", namespace, pod_name, "--", "vault", "status"])
        return f"## Vault Status\n\n```\n{stdout}```\n\n"
    except Exception:  # noqa: BLE001
        return "## Vault Status\n\nUnable to check vault status (pod may not be ready)\n\n"


def _generate_remediation_suggestions(namespace: str) -> str:
    suggestions: list[str] = []
    try:
        stdout, _ = run_command(["oc", "get", "pods", "-n", namespace, "-o", "json"])
        pods = json.loads(stdout)
        items = pods.get("items", [])

        if not items:
            suggestions.append("- No pods found in namespace. Check if deployment was successful.")
        else:
            for pod in items:
                phase = pod.get("status", {}).get("phase")
                name = pod.get("metadata", {}).get("name", "unknown")
                if phase != "Running":
                    suggestions.append(f"- Pod {name} is in {phase} state")
                    for container in pod.get("status", {}).get("containerStatuses", []):
                        waiting = container.get("state", {}).get("waiting")
                        if waiting:
                            suggestions.append(f"- Container waiting: {waiting.get('reason', 'Unknown')}")
    except Exception:  # noqa: BLE001
        suggestions.append("- Unable to analyze pod status automatically")

    if not suggestions:
        suggestions.append("- All checks passed. If issues persist, check application logs.")

    return "\n".join(suggestions) + "\n"
