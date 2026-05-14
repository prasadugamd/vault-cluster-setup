import { exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

interface InitializeVaultArgs {
  namespace: string;
  releaseName: string;
  operation: "init" | "unseal" | "init-and-unseal" | "enable-transit" | "check-seal-status";
  unsealKeys?: string[];
  keyShares?: number;
  keyThreshold?: number;
}

export async function initializeVault(args: any) {
  const {
    namespace,
    releaseName,
    operation,
    unsealKeys = [],
    keyShares = 5,
    keyThreshold = 3,
  } = args as InitializeVaultArgs;

  try {
    switch (operation) {
      case "init":
        return await initVault(namespace, releaseName, keyShares, keyThreshold);
      
      case "unseal":
        return await unsealVault(namespace, releaseName, unsealKeys);
      
      case "init-and-unseal":
        const initResult = await initVault(namespace, releaseName, keyShares, keyThreshold);
        // Parse unseal keys from init result
        // This is a simplified version - real implementation would parse the actual output
        return initResult;
      
      case "enable-transit":
        return await enableTransit(namespace, releaseName);
      
      case "check-seal-status":
        return await checkSealStatus(namespace, releaseName);
      
      default:
        throw new Error(`Unknown operation: ${operation}`);
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text",
          text: `Vault initialization failed: ${errorMessage}`,
        },
      ],
      isError: true,
    };
  }
}

async function initVault(
  namespace: string,
  releaseName: string,
  keyShares: number,
  keyThreshold: number
) {
  const podName = `${releaseName}-0`;
  const command = `oc exec -n ${namespace} ${podName} -- vault operator init -key-shares=${keyShares} -key-threshold=${keyThreshold} -format=json`;

  const { stdout } = await execAsync(command);
  const initData = JSON.parse(stdout);

  let response = `# Vault Initialization Complete\n\n`;
  response += `**Namespace:** ${namespace}\n`;
  response += `**Release Name:** ${releaseName}\n`;
  response += `**Key Shares:** ${keyShares}\n`;
  response += `**Key Threshold:** ${keyThreshold}\n\n`;
  
  response += `## ⚠️ IMPORTANT: Save these keys securely!\n\n`;
  response += `### Unseal Keys\n\n`;
  initData.unseal_keys_b64.forEach((key: string, index: number) => {
    response += `${index + 1}. \`${key}\`\n`;
  });
  
  response += `\n### Root Token\n\n`;
  response += `\`${initData.root_token}\`\n\n`;
  response += `⚠️ Store these credentials in a secure location. You will need the unseal keys to unseal the vault after restarts.\n`;

  return {
    content: [{ type: "text", text: response }],
  };
}

async function unsealVault(
  namespace: string,
  releaseName: string,
  unsealKeys: string[]
) {
  if (unsealKeys.length === 0) {
    throw new Error("Unseal keys are required for unseal operation");
  }

  const podName = `${releaseName}-0`;
  let response = `# Vault Unseal Operation\n\n`;
  response += `**Namespace:** ${namespace}\n`;
  response += `**Release Name:** ${releaseName}\n\n`;

  for (let i = 0; i < unsealKeys.length; i++) {
    const command = `oc exec -n ${namespace} ${podName} -- vault operator unseal ${unsealKeys[i]}`;
    const { stdout } = await execAsync(command);
    response += `**Unseal Key ${i + 1} applied**\n\n\`\`\`\n${stdout}\`\`\`\n\n`;
  }

  return {
    content: [{ type: "text", text: response }],
  };
}

async function enableTransit(namespace: string, releaseName: string) {
  const podName = `${releaseName}-0`;
  const commands = [
    `oc exec -n ${namespace} ${podName} -- vault secrets enable transit`,
    `oc exec -n ${namespace} ${podName} -- vault write -f transit/keys/autounseal`,
  ];

  let response = `# Transit Secrets Engine Setup\n\n`;
  response += `**Namespace:** ${namespace}\n`;
  response += `**Release Name:** ${releaseName}\n\n`;

  for (const command of commands) {
    const { stdout } = await execAsync(command);
    response += `\`\`\`\n${stdout}\`\`\`\n\n`;
  }

  response += `Transit secrets engine enabled and autounseal key created.\n`;

  return {
    content: [{ type: "text", text: response }],
  };
}

async function checkSealStatus(namespace: string, releaseName: string) {
  const podName = `${releaseName}-0`;
  const command = `oc exec -n ${namespace} ${podName} -- vault status -format=json`;

  try {
    const { stdout } = await execAsync(command);
    const status = JSON.parse(stdout);

    let response = `# Vault Seal Status\n\n`;
    response += `**Namespace:** ${namespace}\n`;
    response += `**Release Name:** ${releaseName}\n\n`;
    response += `**Sealed:** ${status.sealed ? "🔒 Yes" : "🔓 No"}\n`;
    response += `**Initialized:** ${status.initialized ? "✅ Yes" : "❌ No"}\n`;
    
    if (!status.sealed) {
      response += `**Cluster:** ${status.cluster_name || "N/A"}\n`;
      response += `**Version:** ${status.version || "N/A"}\n`;
    }

    return {
      content: [{ type: "text", text: response }],
    };
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `Unable to check seal status. Vault may not be running or accessible.`,
        },
      ],
      isError: true,
    };
  }
}
