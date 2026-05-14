from __future__ import annotations

from pathlib import Path
from typing import Any
import shlex

from .common import run_shell, text_response, ToolResponse


def generate_certificates(args: dict[str, Any]) -> ToolResponse:
    namespace = args.get("namespace")
    release_name = args.get("releaseName")
    route = args.get("route")
    operation = args.get("operation", "generate")
    working_directory = args.get("workingDirectory") or str(Path.cwd())

    try:
        if operation == "verify":
            return _verify_certificates(namespace, release_name, working_directory)

        command = (
            f"cd {shlex.quote(working_directory)} && ./generate-certificates.sh "
            f"{shlex.quote(namespace)} {shlex.quote(release_name)}"
        )
        if route:
            command += f" {shlex.quote(route)}"

        stdout, stderr = run_shell(command, cwd=working_directory, max_bytes=5 * 1024 * 1024)

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
        cert_file = Path(working_dir) / f"{namespace}-server.crt"
        command = f"openssl x509 -in {shlex.quote(str(cert_file))} -text -noout"
        stdout, _ = run_shell(command, cwd=working_dir)

        response = "# Certificate Verification\n\n"
        response += f"**Namespace:** {namespace}\n"
        response += f"**Release Name:** {release_name}\n\n"
        response += f"## Certificate Details\n\n```\n{stdout}```\n"
        return text_response(response)
    except Exception:  # noqa: BLE001
        return text_response("Certificate verification failed. Certificates may not exist or are invalid.", is_error=True)
