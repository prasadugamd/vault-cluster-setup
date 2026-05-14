import { exec } from "child_process";
import { promisify } from "util";
import * as path from "path";

const execAsync = promisify(exec);

interface GenerateCertificatesArgs {
  namespace: string;
  releaseName: string;
  route?: string;
  operation?: "generate" | "verify" | "regenerate";
  workingDirectory?: string;
}

export async function generateCertificates(args: any) {
  const {
    namespace,
    releaseName,
    route,
    operation = "generate",
    workingDirectory = process.cwd(),
  } = args as GenerateCertificatesArgs;

  try {
    let command = `cd "${workingDirectory}" && ./generate-certificates.sh ${namespace} ${releaseName}`;
    
    if (route) {
      command += ` ${route}`;
    }

    if (operation === "verify") {
      return await verifyCertificates(namespace, releaseName, workingDirectory);
    }

    // Execute certificate generation
    const { stdout, stderr } = await execAsync(command, {
      cwd: workingDirectory,
      maxBuffer: 1024 * 1024 * 5,
    });

    let response = `# Certificate Generation\n\n`;
    response += `**Namespace:** ${namespace}\n`;
    response += `**Release Name:** ${releaseName}\n`;
    if (route) response += `**Route:** ${route}\n`;
    response += `**Operation:** ${operation}\n\n`;
    
    response += `## Output\n\n\`\`\`\n${stdout}\`\`\`\n`;
    
    if (stderr) {
      response += `\n## Warnings\n\n\`\`\`\n${stderr}\`\`\`\n`;
    }

    response += `\n## Certificate Files Generated\n\n`;
    response += `- CA Certificate: \`${namespace}-ca.crt\`\n`;
    response += `- Server Certificate: \`${namespace}-server.crt\`\n`;
    response += `- Server Key: \`${namespace}-server.key\`\n`;
    response += `- Truststore: \`${namespace}-truststore.jks\`\n`;

    return {
      content: [{ type: "text", text: response }],
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text",
          text: `Certificate operation failed: ${errorMessage}`,
        },
      ],
      isError: true,
    };
  }
}

async function verifyCertificates(
  namespace: string,
  releaseName: string,
  workingDir: string
) {
  try {
    const certFile = path.join(workingDir, `${namespace}-server.crt`);
    const command = `openssl x509 -in "${certFile}" -text -noout`;

    const { stdout } = await execAsync(command, { cwd: workingDir });

    let response = `# Certificate Verification\n\n`;
    response += `**Namespace:** ${namespace}\n`;
    response += `**Release Name:** ${releaseName}\n\n`;
    response += `## Certificate Details\n\n\`\`\`\n${stdout}\`\`\`\n`;

    return {
      content: [{ type: "text", text: response }],
    };
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `Certificate verification failed. Certificates may not exist or are invalid.`,
        },
      ],
      isError: true,
    };
  }
}
