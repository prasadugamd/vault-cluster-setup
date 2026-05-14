from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from .common import text_response, ToolResponse


def manage_vault_config(args: dict[str, Any]) -> ToolResponse:
    operation = args.get("operation")
    config_file = args.get("configFile")
    updates = args.get("updates")
    template = args.get("template")
    working_directory = Path(args.get("workingDirectory") or Path.cwd())

    try:
        if operation == "list":
            return _list_configs(working_directory)
        if operation == "read":
            if not config_file:
                raise ValueError("configFile is required for read operation")
            return _read_config(config_file, working_directory)
        if operation == "create":
            if not config_file:
                raise ValueError("configFile is required for create operation")
            return _create_config(config_file, template, working_directory)
        if operation == "update":
            if not config_file:
                raise ValueError("configFile is required for update operation")
            if not updates:
                raise ValueError("updates is required for update operation")
            return _update_config(config_file, updates, working_directory)
        if operation == "validate":
            if not config_file:
                raise ValueError("configFile is required for validate operation")
            return _validate_config(config_file, working_directory)

        raise ValueError(f"Unknown operation: {operation}")
    except Exception as error:  # noqa: BLE001
        return text_response(f"Configuration operation failed: {error}", is_error=True)


def _list_configs(working_dir: Path) -> ToolResponse:
    config_files = [p.name for p in working_dir.iterdir() if p.is_file() and p.name.startswith("config-") and p.suffix == ".json"]

    response = "# Configuration Files\n\n"
    response += f"Found {len(config_files)} configuration file(s):\n\n"
    for file_name in config_files:
        response += f"- {file_name}\n"

    return text_response(response)


def _read_config(config_file: str, working_dir: Path) -> ToolResponse:
    file_path = working_dir / config_file
    config = json.loads(file_path.read_text(encoding="utf-8"))

    response = f"# Configuration: {config_file}\n\n"
    response += f"```json\n{json.dumps(config, indent=2)}\n```\n"
    return text_response(response)


def _create_config(config_file: str, template: str | None, working_dir: Path) -> ToolResponse:
    file_path = working_dir / config_file

    if template:
        template_path = working_dir / template
        config = json.loads(template_path.read_text(encoding="utf-8"))
    else:
        example_path = working_dir / "config.example.json"
        config = json.loads(example_path.read_text(encoding="utf-8"))

    file_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    return text_response(
        f"Created configuration file: {config_file}\n\nPlease review and update the configuration before deployment."
    )


def _update_config(config_file: str, updates: dict[str, Any], working_dir: Path) -> ToolResponse:
    file_path = working_dir / config_file
    config = json.loads(file_path.read_text(encoding="utf-8"))

    for key, value in updates.items():
        if "." in key:
            parts = key.split(".")
            current = config
            for part in parts[:-1]:
                if part not in current:
                    current[part] = {}
                current = current[part]
            current[parts[-1]] = value
        else:
            config[key] = value

    file_path.write_text(json.dumps(config, indent=2), encoding="utf-8")

    response = f"# Configuration Updated: {config_file}\n\n"
    response += "**Updated fields:**\n"
    for key, value in updates.items():
        response += f"- {key}: {json.dumps(value)}\n"
    response += "\n**New configuration:**\n\n"
    response += f"```json\n{json.dumps(config, indent=2)}\n```\n"

    return text_response(response)


def _validate_config(config_file: str, working_dir: Path) -> ToolResponse:
    file_path = working_dir / config_file

    try:
        config = json.loads(file_path.read_text(encoding="utf-8"))
    except Exception as error:  # noqa: BLE001
        return text_response(f"Invalid JSON in configuration file: {error}", is_error=True)

    required_fields = ["namespace", "releaseName"]
    missing = [field for field in required_fields if not config.get(field)]

    if missing:
        return text_response(
            f"Configuration validation failed\n\nMissing required fields: {', '.join(missing)}",
            is_error=True,
        )

    return text_response(
        f"Configuration is valid\n\n**Namespace:** {config['namespace']}\n**Release Name:** {config['releaseName']}"
    )
