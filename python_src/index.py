#!/usr/bin/env python3
from __future__ import annotations

from typing import Any

from mcp.server.fastmcp import FastMCP

from .tools import (
    check_cluster_status,
    deploy_vault_cluster,
    generate_certificates,
    initialize_vault,
    manage_namespace_route,
    manage_vault_config,
    troubleshoot_deployment,
)


mcp = FastMCP("vault-cluster-mcp-server", version="1.0.0")


def _unwrap_response(response: dict[str, Any]) -> str:
    content = response.get("content", [])
    if content and isinstance(content, list) and isinstance(content[0], dict):
        return str(content[0].get("text", ""))
    return ""


@mcp.tool(name="deploy_vault_cluster")
def tool_deploy_vault_cluster(
    configFiles: list[str],
    deploymentType: str,
    skipCertificates: bool = False,
    skipPrerequisites: bool = False,
    workingDirectory: str | None = None,
) -> str:
    response = deploy_vault_cluster(
        {
            "configFiles": configFiles,
            "deploymentType": deploymentType,
            "skipCertificates": skipCertificates,
            "skipPrerequisites": skipPrerequisites,
            "workingDirectory": workingDirectory,
        }
    )
    return _unwrap_response(response)


@mcp.tool(name="manage_vault_config")
def tool_manage_vault_config(
    operation: str,
    configFile: str | None = None,
    updates: dict[str, Any] | None = None,
    template: str | None = None,
    workingDirectory: str | None = None,
) -> str:
    response = manage_vault_config(
        {
            "operation": operation,
            "configFile": configFile,
            "updates": updates,
            "template": template,
            "workingDirectory": workingDirectory,
        }
    )
    return _unwrap_response(response)


@mcp.tool(name="generate_certificates")
def tool_generate_certificates(
    namespace: str,
    releaseName: str,
    route: str | None = None,
    operation: str = "generate",
    workingDirectory: str | None = None,
) -> str:
    response = generate_certificates(
        {
            "namespace": namespace,
            "releaseName": releaseName,
            "route": route,
            "operation": operation,
            "workingDirectory": workingDirectory,
        }
    )
    return _unwrap_response(response)


@mcp.tool(name="initialize_vault")
def tool_initialize_vault(
    namespace: str,
    releaseName: str,
    operation: str,
    unsealKeys: list[str] | None = None,
    keyShares: int = 5,
    keyThreshold: int = 3,
) -> str:
    response = initialize_vault(
        {
            "namespace": namespace,
            "releaseName": releaseName,
            "operation": operation,
            "unsealKeys": unsealKeys or [],
            "keyShares": keyShares,
            "keyThreshold": keyThreshold,
        }
    )
    return _unwrap_response(response)


@mcp.tool(name="troubleshoot_deployment")
def tool_troubleshoot_deployment(
    namespace: str,
    releaseName: str | None = None,
    checkType: str = "all",
    podName: str | None = None,
) -> str:
    response = troubleshoot_deployment(
        {
            "namespace": namespace,
            "releaseName": releaseName,
            "checkType": checkType,
            "podName": podName,
        }
    )
    return _unwrap_response(response)


@mcp.tool(name="check_cluster_status")
def tool_check_cluster_status(
    namespace: str | None = None,
    releaseName: str | None = None,
    detailed: bool = False,
) -> str:
    response = check_cluster_status(
        {
            "namespace": namespace,
            "releaseName": releaseName,
            "detailed": detailed,
        }
    )
    return _unwrap_response(response)


@mcp.tool(name="manage_namespace_route")
def tool_manage_namespace_route(
    operation: str,
    namespace: str,
    releaseName: str | None = None,
    route: str | None = None,
    workingDirectory: str | None = None,
) -> str:
    response = manage_namespace_route(
        {
            "operation": operation,
            "namespace": namespace,
            "releaseName": releaseName,
            "route": route,
            "workingDirectory": workingDirectory,
        }
    )
    return _unwrap_response(response)


def main() -> None:
    mcp.run()


if __name__ == "__main__":
    main()
