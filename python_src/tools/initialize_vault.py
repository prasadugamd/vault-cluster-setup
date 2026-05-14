from __future__ import annotations

import json
from typing import Any

from .common import run_shell, text_response, ToolResponse


def initialize_vault(args: dict[str, Any]) -> ToolResponse:
    namespace = args.get("namespace")
    release_name = args.get("releaseName")
    operation = args.get("operation")
    unseal_keys = args.get("unsealKeys", [])
    key_shares = int(args.get("keyShares", 5))
    key_threshold = int(args.get("keyThreshold", 3))

    try:
        if operation == "init":
            return _init_vault(namespace, release_name, key_shares, key_threshold)
        if operation == "unseal":
            return _unseal_vault(namespace, release_name, unseal_keys)
        if operation == "init-and-unseal":
            return _init_vault(namespace, release_name, key_shares, key_threshold)
        if operation == "enable-transit":
            return _enable_transit(namespace, release_name)
        if operation == "check-seal-status":
            return _check_seal_status(namespace, release_name)

        raise ValueError(f"Unknown operation: {operation}")
    except Exception as error:  # noqa: BLE001
        return text_response(f"Vault initialization failed: {error}", is_error=True)


def _init_vault(namespace: str, release_name: str, key_shares: int, key_threshold: int) -> ToolResponse:
    pod_name = f"{release_name}-0"
    command = (
        f"oc exec -n {namespace} {pod_name} -- vault operator init "
        f"-key-shares={key_shares} -key-threshold={key_threshold} -format=json"
    )
    stdout, _ = run_shell(command)
    init_data = json.loads(stdout)

    response = "# Vault Initialization Complete\n\n"
    response += f"**Namespace:** {namespace}\n"
    response += f"**Release Name:** {release_name}\n"
    response += f"**Key Shares:** {key_shares}\n"
    response += f"**Key Threshold:** {key_threshold}\n\n"
    response += "## IMPORTANT: Save these keys securely!\n\n"
    response += "### Unseal Keys\n\n"
    for index, key in enumerate(init_data.get("unseal_keys_b64", []), start=1):
        response += f"{index}. `{key}`\n"

    response += "\n### Root Token\n\n"
    response += f"`{init_data.get('root_token', '')}`\n\n"
    response += "Store these credentials in a secure location. You will need unseal keys after restarts.\n"
    return text_response(response)


def _unseal_vault(namespace: str, release_name: str, unseal_keys: list[str]) -> ToolResponse:
    if not unseal_keys:
        raise ValueError("Unseal keys are required for unseal operation")

    pod_name = f"{release_name}-0"
    response = "# Vault Unseal Operation\n\n"
    response += f"**Namespace:** {namespace}\n"
    response += f"**Release Name:** {release_name}\n\n"

    for index, key in enumerate(unseal_keys, start=1):
        command = f"oc exec -n {namespace} {pod_name} -- vault operator unseal {key}"
        stdout, _ = run_shell(command)
        response += f"**Unseal Key {index} applied**\n\n```\n{stdout}```\n\n"

    return text_response(response)


def _enable_transit(namespace: str, release_name: str) -> ToolResponse:
    pod_name = f"{release_name}-0"
    commands = [
        f"oc exec -n {namespace} {pod_name} -- vault secrets enable transit",
        f"oc exec -n {namespace} {pod_name} -- vault write -f transit/keys/autounseal",
    ]

    response = "# Transit Secrets Engine Setup\n\n"
    response += f"**Namespace:** {namespace}\n"
    response += f"**Release Name:** {release_name}\n\n"

    for command in commands:
        stdout, _ = run_shell(command)
        response += f"```\n{stdout}```\n\n"

    response += "Transit secrets engine enabled and autounseal key created.\n"
    return text_response(response)


def _check_seal_status(namespace: str, release_name: str) -> ToolResponse:
    pod_name = f"{release_name}-0"
    command = f"oc exec -n {namespace} {pod_name} -- vault status -format=json"

    try:
        stdout, _ = run_shell(command)
        status = json.loads(stdout)

        response = "# Vault Seal Status\n\n"
        response += f"**Namespace:** {namespace}\n"
        response += f"**Release Name:** {release_name}\n\n"
        response += f"**Sealed:** {'Yes' if status.get('sealed') else 'No'}\n"
        response += f"**Initialized:** {'Yes' if status.get('initialized') else 'No'}\n"

        if not status.get("sealed"):
            response += f"**Cluster:** {status.get('cluster_name', 'N/A')}\n"
            response += f"**Version:** {status.get('version', 'N/A')}\n"

        return text_response(response)
    except Exception:  # noqa: BLE001
        return text_response("Unable to check seal status. Vault may not be running or accessible.", is_error=True)
