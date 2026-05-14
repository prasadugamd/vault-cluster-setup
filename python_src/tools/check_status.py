from __future__ import annotations

import json
from typing import Any

from .common import run_shell, text_response, ToolResponse


def check_cluster_status(args: dict[str, Any]) -> ToolResponse:
    namespace = args.get("namespace")
    release_name = args.get("releaseName")
    detailed = bool(args.get("detailed", False))

    try:
        response = "# Cluster Status Check\n\n"

        response += "## Cluster Connectivity\n\n"
        try:
            stdout, _ = run_shell("oc cluster-info")
            response += f"Connected to cluster\n\n```\n{stdout}```\n\n"
        except Exception:
            response += "Not connected to cluster\n\n"
            return text_response(response, is_error=True)

        if namespace:
            response += f"## Namespace: {namespace}\n\n"

            try:
                pod_command = f"oc get pods -n {namespace}"
                if release_name:
                    pod_command += f" -l app.kubernetes.io/instance={release_name}"
                pod_status, _ = run_shell(pod_command)
                response += f"### Pods\n\n```\n{pod_status}```\n\n"
            except Exception:
                response += "### Pods\n\nUnable to retrieve pods\n\n"

            if release_name:
                try:
                    svc_status, _ = run_shell(f"oc get svc -n {namespace} -l app.kubernetes.io/instance={release_name}")
                    response += f"### Services\n\n```\n{svc_status}```\n\n"
                except Exception:
                    response += "### Services\n\nUnable to retrieve services\n\n"

                try:
                    route_status, _ = run_shell(f"oc get route -n {namespace}")
                    response += f"### Routes\n\n```\n{route_status}```\n\n"
                except Exception:
                    response += "### Routes\n\nNo routes found\n\n"

                if detailed:
                    response += "### Vault Status\n\n"
                    try:
                        vault_status, _ = run_shell(f"oc exec -n {namespace} {release_name}-0 -- vault status")
                        response += f"```\n{vault_status}```\n\n"
                    except Exception:
                        response += "Unable to check vault status\n\n"

                response += "### Helm Release\n\n"
                try:
                    helm_status, _ = run_shell(f"helm list -n {namespace} -f {release_name}")
                    response += f"```\n{helm_status}```\n\n"
                except Exception:
                    response += "Unable to retrieve helm release info\n\n"

        response += "## Health Summary\n\n"
        response += _generate_health_summary(namespace, release_name)

        return text_response(response)
    except Exception as error:  # noqa: BLE001
        return text_response(f"Status check failed: {error}", is_error=True)


def _generate_health_summary(namespace: str | None, release_name: str | None) -> str:
    if not namespace:
        return "Cluster is accessible\nSpecify namespace for detailed health check\n"

    try:
        selector = f"-l app.kubernetes.io/instance={release_name}" if release_name else ""
        stdout, _ = run_shell(f"oc get pods -n {namespace} {selector} -o json")
        pods = json.loads(stdout)
        items = pods.get("items", [])

        if not items:
            return "No pods found\n"

        total = len(items)
        running = len([p for p in items if p.get("status", {}).get("phase") == "Running"])

        def is_ready(pod: dict[str, Any]) -> bool:
            return any(
                cond.get("type") == "Ready" and cond.get("status") == "True"
                for cond in pod.get("status", {}).get("conditions", [])
            )

        ready = len([p for p in items if is_ready(p)])

        summary = f"**Pods:** {running}/{total} running, {ready}/{total} ready\n"
        if running == total and ready == total:
            summary += "All pods are healthy\n"
        else:
            summary += "Some pods are not healthy\n"
        return summary
    except Exception:
        return "Unable to generate health summary\n"
