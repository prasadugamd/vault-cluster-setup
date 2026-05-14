import { exec } from "child_process";
import { promisify } from "util";
import * as path from "path";

const execAsync = promisify(exec);

interface ManageNamespaceRouteArgs {
  operation: "create" | "delete" | "check";
  namespace: string;
  releaseName?: string;
  route?: string;
  workingDirectory?: string;
}

export async function manageNamespaceRoute(args: any) {
  const {
    operation,
    namespace,
    releaseName,
    route,
    workingDirectory = process.cwd(),
  } = args as ManageNamespaceRouteArgs;

  try {
    switch (operation) {
      case "create":
        return await createNamespaceRoute(namespace, releaseName, route, workingDirectory);
      
      case "delete":
        return await deleteNamespaceRoute(namespace);
      
      case "check":
        return await checkNamespaceRoute(namespace);
      
      default:
        throw new Error(`Unknown operation: ${operation}`);
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text",
          text: `Namespace/route operation failed: ${errorMessage}`,
        },
      ],
      isError: true,
    };
  }
}

async function createNamespaceRoute(
  namespace: string,
  releaseName: string | undefined,
  route: string | undefined,
  workingDir: string
) {
  let command = `cd "${workingDir}" && ./create-namespace-route.sh ${namespace}`;
  
  if (releaseName) {
    command += ` ${releaseName}`;
  }
  
  if (route) {
    command += ` ${route}`;
  }

  const { stdout, stderr } = await execAsync(command, {
    cwd: workingDir,
    maxBuffer: 1024 * 1024 * 5,
  });

  let response = `# Namespace and Route Creation\n\n`;
  response += `**Namespace:** ${namespace}\n`;
  if (releaseName) response += `**Release Name:** ${releaseName}\n`;
  if (route) response += `**Route:** ${route}\n\n`;
  
  response += `## Output\n\n\`\`\`\n${stdout}\`\`\`\n`;
  
  if (stderr) {
    response += `\n## Warnings\n\n\`\`\`\n${stderr}\`\`\`\n`;
  }

  return {
    content: [{ type: "text", text: response }],
  };
}

async function deleteNamespaceRoute(namespace: string) {
  const command = `oc delete namespace ${namespace}`;

  try {
    const { stdout } = await execAsync(command);
    
    let response = `# Namespace Deletion\n\n`;
    response += `**Namespace:** ${namespace}\n\n`;
    response += `✅ Namespace deleted successfully\n\n`;
    response += `\`\`\`\n${stdout}\`\`\`\n`;

    return {
      content: [{ type: "text", text: response }],
    };
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `Failed to delete namespace ${namespace}. It may not exist or there may be resources preventing deletion.`,
        },
      ],
      isError: true,
    };
  }
}

async function checkNamespaceRoute(namespace: string) {
  let response = `# Namespace and Route Status\n\n`;
  response += `**Namespace:** ${namespace}\n\n`;

  // Check namespace
  try {
    const { stdout: nsStatus } = await execAsync(`oc get namespace ${namespace}`);
    response += `## Namespace Status\n\n\`\`\`\n${nsStatus}\`\`\`\n\n`;
  } catch (error) {
    response += `## Namespace Status\n\n❌ Namespace does not exist\n\n`;
    return {
      content: [{ type: "text", text: response }],
      isError: true,
    };
  }

  // Check routes in namespace
  try {
    const { stdout: routeStatus } = await execAsync(`oc get routes -n ${namespace}`);
    response += `## Routes\n\n\`\`\`\n${routeStatus}\`\`\`\n\n`;
  } catch (error) {
    response += `## Routes\n\n❌ No routes found or unable to retrieve\n\n`;
  }

  return {
    content: [{ type: "text", text: response }],
  };
}
