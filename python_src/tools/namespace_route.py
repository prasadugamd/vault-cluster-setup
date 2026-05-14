from __future__ import annotations

from pathlib import Path
from typing import Any
import shlex

from .common import run_shell, text_response, ToolResponse


def manage_namespace_route(args: dict[str, Any]) -> ToolResponse:
    operation = args.get("operation")
    namespace = args.get("namespace")
    release_name = args.get("releaseName")
    route = args.get("route")
    working_directory = args.get("workingDirectory") or str(Path.cwd())

    try:
        if operation == "create":
            return _create_namespace_route(namespace, release_name, route, working_directory)
        if operation == "delete":
            return _delete_namespace_route(namespace)
        if operation == "check":
            return _check_namespace_route(namespace)

        raise ValueError(f"Unknown operation: {operation}")
    except Exception as error:  # noqa: BLE001
        return text_response(f"Namespace/route operation failed: {error}", is_error=True)


def _create_namespace_route(namespace: str, release_name: str | None, route: str | None, working_dir: str) -> ToolResponse:
    command = f"cd {shlex.quote(working_dir)} && ./create-namespace-route.sh {shlex.quote(namespace)}"
    if release_name:
        command += f" {shlex.quote(release_name)}"
    if route:
        command += f" {shlex.quote(route)}"

    stdout, stderr = run_shell(command, cwd=working_dir, max_bytes=5 * 1024 * 1024)

    response = "# Namespace and Route Creation\n\n"
    response += f"**Namespace:** {namespace}\n"
    if release_name:
        response += f"**Release Name:** {release_name}\n"
    if route:
        response += f"**Route:** {route}\n\n"

    response += f"## Output\n\n```\n{stdout}```\n"
    if stderr:
        response += f"\n## Warnings\n\n```\n{stderr}```\n"

    return text_response(response)


def _delete_namespace_route(namespace: str) -> ToolResponse:
    command = f"oc delete namespace {namespace}"

    try:
        stdout, _ = run_shell(command)
        response = "# Namespace Deletion\n\n"
        response += f"**Namespace:** {namespace}\n\n"
        response += "Namespace deleted successfully\n\n"
        response += f"```\n{stdout}```\n"
        return text_response(response)
    except Exception:  # noqa: BLE001
        return text_response(
            f"Failed to delete namespace {namespace}. It may not exist or there may be resources preventing deletion.",
            is_error=True,
        )


def _check_namespace_route(namespace: str) -> ToolResponse:
    response = "# Namespace and Route Status\n\n"
    response += f"**Namespace:** {namespace}\n\n"

    try:
        ns_status, _ = run_shell(f"oc get namespace {namespace}")
        response += f"## Namespace Status\n\n```\n{ns_status}```\n\n"
    except Exception:  # noqa: BLE001
        response += "## Namespace Status\n\nNamespace does not exist\n\n"
        return text_response(response, is_error=True)

    try:
        route_status, _ = run_shell(f"oc get routes -n {namespace}")
        response += f"## Routes\n\n```\n{route_status}```\n\n"
    except Exception:  # noqa: BLE001
        response += "## Routes\n\nNo routes found or unable to retrieve\n\n"

    return text_response(response)
