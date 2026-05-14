import { exec } from "child_process";
import { promisify } from "util";

const execAsync = promisify(exec);

interface CheckClusterStatusArgs {
  namespace?: string;
  releaseName?: string;
  detailed?: boolean;
}

export async function checkClusterStatus(args: any) {
  const {
    namespace,
    releaseName,
    detailed = false,
  } = args as CheckClusterStatusArgs;

  try {
    let response = `# Cluster Status Check\n\n`;

    // Check cluster connectivity
    response += `## Cluster Connectivity\n\n`;
    try {
      const { stdout } = await execAsync("oc cluster-info");
      response += `✅ Connected to cluster\n\n\`\`\`\n${stdout}\`\`\`\n\n`;
    } catch (error) {
      response += `❌ Not connected to cluster\n\n`;
      return {
        content: [{ type: "text", text: response }],
        isError: true,
      };
    }

    // Check namespace-specific resources
    if (namespace) {
      response += `## Namespace: ${namespace}\n\n`;
      
      // Check pods
      try {
        let podCommand = `oc get pods -n ${namespace}`;
        if (releaseName) {
          podCommand += ` -l app.kubernetes.io/instance=${releaseName}`;
        }
        const { stdout: podStatus } = await execAsync(podCommand);
        response += `### Pods\n\n\`\`\`\n${podStatus}\`\`\`\n\n`;
      } catch (error) {
        response += `### Pods\n\n❌ Unable to retrieve pods\n\n`;
      }

      // Check services
      if (releaseName) {
        try {
          const { stdout: svcStatus } = await execAsync(
            `oc get svc -n ${namespace} -l app.kubernetes.io/instance=${releaseName}`
          );
          response += `### Services\n\n\`\`\`\n${svcStatus}\`\`\`\n\n`;
        } catch (error) {
          response += `### Services\n\n❌ Unable to retrieve services\n\n`;
        }
      }

      // Check routes
      if (releaseName) {
        try {
          const { stdout: routeStatus } = await execAsync(
            `oc get route -n ${namespace}`
          );
          response += `### Routes\n\n\`\`\`\n${routeStatus}\`\`\`\n\n`;
        } catch (error) {
          response += `### Routes\n\n❌ No routes found\n\n`;
        }
      }

      // Check Vault status if specified
      if (releaseName && detailed) {
        response += `### Vault Status\n\n`;
        try {
          const { stdout: vaultStatus } = await execAsync(
            `oc exec -n ${namespace} ${releaseName}-0 -- vault status`
          );
          response += `\`\`\`\n${vaultStatus}\`\`\`\n\n`;
        } catch (error) {
          response += `❌ Unable to check vault status\n\n`;
        }
      }

      // Check Helm releases
      if (releaseName) {
        response += `### Helm Release\n\n`;
        try {
          const { stdout: helmStatus } = await execAsync(
            `helm list -n ${namespace} -f ${releaseName}`
          );
          response += `\`\`\`\n${helmStatus}\`\`\`\n\n`;
        } catch (error) {
          response += `❌ Unable to retrieve helm release info\n\n`;
        }
      }
    }

    // Overall health summary
    response += `## Health Summary\n\n`;
    response += await generateHealthSummary(namespace, releaseName);

    return {
      content: [{ type: "text", text: response }],
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text",
          text: `Status check failed: ${errorMessage}`,
        },
      ],
      isError: true,
    };
  }
}

async function generateHealthSummary(namespace?: string, releaseName?: string) {
  let summary = ``;
  
  if (!namespace) {
    summary += `✅ Cluster is accessible\n`;
    summary += `ℹ️ Specify namespace for detailed health check\n`;
    return summary;
  }

  try {
    const { stdout } = await execAsync(
      `oc get pods -n ${namespace} ${releaseName ? `-l app.kubernetes.io/instance=${releaseName}` : ""} -o json`
    );
    const pods = JSON.parse(stdout);
    
    if (!pods.items || pods.items.length === 0) {
      summary += `⚠️ No pods found\n`;
      return summary;
    }

    const totalPods = pods.items.length;
    const runningPods = pods.items.filter((p: any) => p.status.phase === "Running").length;
    const readyPods = pods.items.filter((p: any) => 
      p.status.conditions?.some((c: any) => c.type === "Ready" && c.status === "True")
    ).length;

    summary += `**Pods:** ${runningPods}/${totalPods} running, ${readyPods}/${totalPods} ready\n`;
    
    if (runningPods === totalPods && readyPods === totalPods) {
      summary += `✅ All pods are healthy\n`;
    } else {
      summary += `⚠️ Some pods are not healthy\n`;
    }
  } catch (error) {
    summary += `❌ Unable to generate health summary\n`;
  }

  return summary;
}
