import { exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

interface TroubleshootDeploymentArgs {
  namespace: string;
  releaseName?: string;
  checkType?: "all" | "pods" | "logs" | "helm" | "route" | "certificates" | "vault-status";
  podName?: string;
}

export async function troubleshootDeployment(args: any) {
  const {
    namespace,
    releaseName,
    checkType = "all",
    podName,
  } = args as TroubleshootDeploymentArgs;

  try {
    let response = `# Troubleshooting: ${namespace}\n\n`;
    
    if (checkType === "all" || checkType === "pods") {
      response += await checkPods(namespace, releaseName);
    }
    
    if (checkType === "all" || checkType === "logs") {
      if (podName) {
        response += await getPodLogs(namespace, podName);
      } else if (releaseName) {
        response += await getPodLogs(namespace, `${releaseName}-0`);
      }
    }
    
    if (checkType === "all" || checkType === "helm") {
      if (releaseName) {
        response += await checkHelmRelease(namespace, releaseName);
      }
    }
    
    if (checkType === "all" || checkType === "route") {
      if (releaseName) {
        response += await checkRoute(namespace, releaseName);
      }
    }
    
    if (checkType === "vault-status") {
      if (releaseName) {
        response += await checkVaultStatus(namespace, releaseName);
      }
    }

    response += `\n## Remediation Suggestions\n\n`;
    response += await generateRemediationSuggestions(namespace, releaseName);

    return {
      content: [{ type: "text", text: response }],
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text",
          text: `Troubleshooting failed: ${errorMessage}`,
        },
      ],
      isError: true,
    };
  }
}

async function checkPods(namespace: string, releaseName?: string) {
  let command = `oc get pods -n ${namespace}`;
  if (releaseName) {
    command += ` -l app.kubernetes.io/instance=${releaseName}`;
  }
  command += ` -o wide`;

  try {
    const { stdout } = await execAsync(command);
    return `## Pod Status\n\n\`\`\`\n${stdout}\`\`\`\n\n`;
  } catch (error) {
    return `## Pod Status\n\n❌ Unable to retrieve pod status\n\n`;
  }
}

async function getPodLogs(namespace: string, podName: string) {
  const command = `oc logs -n ${namespace} ${podName} --tail=100`;

  try {
    const { stdout } = await execAsync(command);
    return `## Pod Logs: ${podName}\n\n\`\`\`\n${stdout}\`\`\`\n\n`;
  } catch (error) {
    return `## Pod Logs: ${podName}\n\n❌ Unable to retrieve logs\n\n`;
  }
}

async function checkHelmRelease(namespace: string, releaseName: string) {
  const command = `helm status ${releaseName} -n ${namespace}`;

  try {
    const { stdout } = await execAsync(command);
    return `## Helm Release Status\n\n\`\`\`\n${stdout}\`\`\`\n\n`;
  } catch (error) {
    return `## Helm Release Status\n\n❌ Release not found or error occurred\n\n`;
  }
}

async function checkRoute(namespace: string, releaseName: string) {
  const command = `oc get route -n ${namespace} ${releaseName}-route -o wide`;

  try {
    const { stdout } = await execAsync(command);
    return `## Route Status\n\n\`\`\`\n${stdout}\`\`\`\n\n`;
  } catch (error) {
    return `## Route Status\n\n❌ Route not found\n\n`;
  }
}

async function checkVaultStatus(namespace: string, releaseName: string) {
  const podName = `${releaseName}-0`;
  const command = `oc exec -n ${namespace} ${podName} -- vault status`;

  try {
    const { stdout } = await execAsync(command);
    return `## Vault Status\n\n\`\`\`\n${stdout}\`\`\`\n\n`;
  } catch (error) {
    return `## Vault Status\n\n❌ Unable to check vault status (pod may not be ready)\n\n`;
  }
}

async function generateRemediationSuggestions(namespace: string, releaseName?: string) {
  let suggestions = ``;
  
  // Check common issues
  try {
    const { stdout } = await execAsync(`oc get pods -n ${namespace} -o json`);
    const pods = JSON.parse(stdout);
    
    if (pods.items && pods.items.length === 0) {
      suggestions += `- No pods found in namespace. Check if deployment was successful.\n`;
    } else {
      pods.items.forEach((pod: any) => {
        if (pod.status.phase !== "Running") {
          suggestions += `- Pod ${pod.metadata.name} is in ${pod.status.phase} state\n`;
          
          if (pod.status.containerStatuses) {
            pod.status.containerStatuses.forEach((container: any) => {
              if (container.state.waiting) {
                suggestions += `  - Container waiting: ${container.state.waiting.reason}\n`;
              }
            });
          }
        }
      });
    }
  } catch (error) {
    suggestions += `- Unable to analyze pod status automatically\n`;
  }

  if (!suggestions) {
    suggestions = `- All checks passed. If issues persist, check application logs.\n`;
  }

  return suggestions;
}
