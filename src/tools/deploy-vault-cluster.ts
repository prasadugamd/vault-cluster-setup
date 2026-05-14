import { exec } from "child_process";
import { promisify } from "util";
import * as path from "path";

const execAsync = promisify(exec);

interface DeployVaultClusterArgs {
  configFiles: string[];
  deploymentType: "complete" | "unsealer-only" | "data-vault";
  skipCertificates?: boolean;
  skipPrerequisites?: boolean;
  workingDirectory?: string;
}

export async function deployVaultCluster(args: any) {
  const {
    configFiles,
    deploymentType,
    skipCertificates = false,
    skipPrerequisites = false,
    workingDirectory = process.cwd(),
  } = args as DeployVaultClusterArgs;

  try {
    // Validate config files exist
    const configFilePaths = configFiles.map((f) => path.join(workingDirectory, f));
    
    // Build the deployment command
    let command = `cd "${workingDirectory}" && ./setup-vault-cluster.sh`;
    
    // Add configuration files
    configFilePaths.forEach((configPath) => {
      command += ` ${path.basename(configPath)}`;
    });
    
    // Add flags
    if (skipCertificates) {
      command += " --skip-certificates";
    }
    if (skipPrerequisites) {
      command += " --skip-prerequisites";
    }

    // Execute deployment
    const { stdout, stderr } = await execAsync(command, {
      cwd: workingDirectory,
      maxBuffer: 1024 * 1024 * 10, // 10MB buffer for large outputs
    });

    let response = `# Vault Cluster Deployment\n\n`;
    response += `**Deployment Type:** ${deploymentType}\n`;
    response += `**Configuration Files:** ${configFiles.join(", ")}\n\n`;
    response += `## Deployment Output\n\n\`\`\`\n${stdout}\`\`\`\n`;
    
    if (stderr) {
      response += `\n## Warnings/Errors\n\n\`\`\`\n${stderr}\`\`\`\n`;
    }

    response += `\n## Next Steps\n\n`;
    if (deploymentType === "unsealer-only" || deploymentType === "complete") {
      response += `1. Initialize the unsealer vault: Use \`initialize_vault\` tool\n`;
      response += `2. Enable transit secrets engine\n`;
    }
    if (deploymentType === "data-vault" || deploymentType === "complete") {
      response += `3. Verify data vault auto-unsealed\n`;
      response += `4. Check cluster status with \`check_cluster_status\` tool\n`;
    }

    return {
      content: [
        {
          type: "text",
          text: response,
        },
      ],
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text",
          text: `Deployment failed: ${errorMessage}\n\nUse the troubleshoot_deployment tool to diagnose issues.`,
        },
      ],
      isError: true,
    };
  }
}
