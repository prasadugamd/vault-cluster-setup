from __future__ import annotations

from pathlib import Path
from typing import Any

from .common import run_command, text_response, ToolResponse, require_ident


def generate_certificates(args: dict[str, Any]) -> ToolResponse:
    route = args.get("route")
    operation = args.get("operation", "generate")
    working_directory = args.get("workingDirectory") or str(Path.cwd())

    try:
        namespace = require_ident(args.get("namespace"), "namespace")
        release_name = require_ident(args.get("releaseName"), "releaseName")
        if route:
            route = require_ident(route, "route")

        if operation == "verify":
            return _verify_certificates(namespace, release_name, working_directory)

        command = ["./generate-certificates.sh", namespace, release_name]
        if route:
            command.append(route)

        stdout, stderr = run_command(command, cwd=working_directory, max_bytes=5 * 1024 * 1024)

        response = "# Certificate Generation\n\n"
        response += f"**Namespace:** {namespace}\n"
        response += f"**Release Name:** {release_name}\n"
        if route:
            response += f"**Route:** {route}\n"
        response += f"**Operation:** {operation}\n\n"
        response += f"## Output\n\n```\n{stdout}```\n"

        if stderr:
            response += f"\n## Warnings\n\n```\n{stderr}```\n"

        response += "\n## Certificate Files Generated\n\n"
        response += f"- CA Certificate: `{namespace}-ca.crt`\n"
        response += f"- Server Certificate: `{namespace}-server.crt`\n"
        response += f"- Server Key: `{namespace}-server.key`\n"
        response += f"- Truststore: `{namespace}-truststore.jks`\n"

        return text_response(response)
    except Exception as error:  # noqa: BLE001
        return text_response(f"Certificate operation failed: {error}", is_error=True)


def _verify_certificates(namespace: str, release_name: str, working_dir: str) -> ToolResponse:
    try:
        work = Path(working_dir).resolve()
        cert_file = (work / f"{namespace}-server.crt").resolve()
        if work not in cert_file.parents:
            raise ValueError("Certificate path is outside the working directory")

        stdout, _ = run_command(
            ["openssl", "x509", "-in", str(cert_file), "-text", "-noout"],
            cwd=str(work),
        )

        response = "# Certificate Verification\n\n"
        response += f"**Namespace:** {namespace}\n"
        response += f"**Release Name:** {release_name}\n\n"
        response += f"## Certificate Details\n\n```\n{stdout}```\n"
        return text_response(response)
    except Exception:  # noqa: BLE001
        return text_response("Certificate verification failed. Certificates may not exist or are invalid.", is_error=True)
