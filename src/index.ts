#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";
import { deployVaultCluster } from "./tools/deploy-vault-cluster.js";
import { manageVaultConfig } from "./tools/manage-config.js";
import { generateCertificates } from "./tools/generate-certificates.js";
import { initializeVault } from "./tools/initialize-vault.js";
import { troubleshootDeployment } from "./tools/troubleshoot.js";
import { checkClusterStatus } from "./tools/check-status.js";
import { manageNamespaceRoute } from "./tools/namespace-route.js";

/**
 * Vault Cluster MCP Server
 * 
 * Provides tools for automating HashiCorp Vault cluster deployments
 * on OpenShift/Kubernetes platforms.
 */

const server = new Server(
  {
    name: "vault-cluster-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

/**
 * Tool definitions for the MCP server
 */
const tools: Tool[] = [
  {
    name: "deploy_vault_cluster",
    description: "Deploy a complete HashiCorp Vault cluster or individual components (unsealer vault, data vault). Executes deployment scripts with specified configuration files.",
    inputSchema: {
      type: "object",
      properties: {
        configFiles: {
          type: "array",
          items: { type: "string" },
          description: "Array of configuration file paths (e.g., ['config-unsealer-vault.json', 'config-vault-1.json'])",
        },
        deploymentType: {
          type: "string",
          enum: ["complete", "unsealer-only", "data-vault"],
          description: "Type of deployment: complete (unsealer + data), unsealer-only, or data-vault",
        },
        skipCertificates: {
          type: "boolean",
          description: "Skip certificate generation if certificates already exist",
          default: false,
        },
        skipPrerequisites: {
          type: "boolean",
          description: "Skip prerequisites deployment",
          default: false,
        },
        workingDirectory: {
          type: "string",
          description: "Working directory containing deployment scripts (defaults to current directory)",
        },
      },
      required: ["configFiles", "deploymentType"],
    },
  },
  {
    name: "manage_vault_config",
    description: "Create, read, update, or validate Vault configuration JSON files. Supports modifying namespace, release name, replicas, routes, and other deployment parameters.",
    inputSchema: {
      type: "object",
      properties: {
        operation: {
          type: "string",
          enum: ["read", "create", "update", "validate", "list"],
          description: "Operation to perform on configuration files",
        },
        configFile: {
          type: "string",
          description: "Configuration file path (e.g., 'config-vault-1.json')",
        },
        updates: {
          type: "object",
          description: "Key-value pairs to update in the configuration (for update operation)",
          additionalProperties: true,
        },
        template: {
          type: "string",
          description: "Template to use when creating new config (for create operation)",
        },
        workingDirectory: {
          type: "string",
          description: "Working directory containing config files",
        },
      },
      required: ["operation"],
    },
  },
  {
    name: "generate_certificates",
    description: "Generate TLS certificates for Vault clusters including CA, server certificates, and truststore. Supports certificate verification and regeneration.",
    inputSchema: {
      type: "object",
      properties: {
        namespace: {
          type: "string",
          description: "Kubernetes/OpenShift namespace for the vault deployment",
        },
        releaseName: {
          type: "string",
          description: "Helm release name for the vault",
        },
        route: {
          type: "string",
          description: "OpenShift route hostname for external access",
        },
        operation: {
          type: "string",
          enum: ["generate", "verify", "regenerate"],
          description: "Certificate operation to perform",
          default: "generate",
        },
        workingDirectory: {
          type: "string",
          description: "Working directory containing certificate generation scripts",
        },
      },
      required: ["namespace", "releaseName"],
    },
  },
  {
    name: "initialize_vault",
    description: "Initialize a Vault cluster, unseal it, and configure transit auto-unseal. Handles key management and initial setup.",
    inputSchema: {
      type: "object",
      properties: {
        namespace: {
          type: "string",
          description: "Kubernetes/OpenShift namespace containing the vault",
        },
        releaseName: {
          type: "string",
          description: "Helm release name of the vault to initialize",
        },
        operation: {
          type: "string",
          enum: ["init", "unseal", "init-and-unseal", "enable-transit", "check-seal-status"],
          description: "Initialization operation to perform",
        },
        unsealKeys: {
          type: "array",
          items: { type: "string" },
          description: "Unseal keys (required for unseal operation)",
        },
        keyShares: {
          type: "number",
          description: "Number of key shares to generate (default: 5)",
          default: 5,
        },
        keyThreshold: {
          type: "number",
          description: "Number of keys required to unseal (default: 3)",
          default: 3,
        },
      },
      required: ["namespace", "releaseName", "operation"],
    },
  },
  {
    name: "troubleshoot_deployment",
    description: "Diagnose and troubleshoot Vault deployment issues. Checks pod status, logs, helm releases, routes, and provides remediation suggestions.",
    inputSchema: {
      type: "object",
      properties: {
        namespace: {
          type: "string",
          description: "Kubernetes/OpenShift namespace to troubleshoot",
        },
        releaseName: {
          type: "string",
          description: "Helm release name to troubleshoot",
        },
        checkType: {
          type: "string",
          enum: ["all", "pods", "logs", "helm", "route", "certificates", "vault-status"],
          description: "Type of diagnostic check to perform",
          default: "all",
        },
        podName: {
          type: "string",
          description: "Specific pod name for log retrieval",
        },
      },
      required: ["namespace"],
    },
  },
  {
    name: "check_cluster_status",
    description: "Check the overall health and status of Vault cluster components including connectivity, pods, services, routes, and Vault seal status.",
    inputSchema: {
      type: "object",
      properties: {
        namespace: {
          type: "string",
          description: "Kubernetes/OpenShift namespace to check",
        },
        releaseName: {
          type: "string",
          description: "Helm release name to check",
        },
        detailed: {
          type: "boolean",
          description: "Provide detailed status information",
          default: false,
        },
      },
    },
  },
  {
    name: "manage_namespace_route",
    description: "Create or manage OpenShift namespace and route for Vault external access.",
    inputSchema: {
      type: "object",
      properties: {
        operation: {
          type: "string",
          enum: ["create", "delete", "check"],
          description: "Namespace/route operation to perform",
        },
        namespace: {
          type: "string",
          description: "Kubernetes/OpenShift namespace",
        },
        releaseName: {
          type: "string",
          description: "Helm release name",
        },
        route: {
          type: "string",
          description: "OpenShift route hostname",
        },
        workingDirectory: {
          type: "string",
          description: "Working directory containing scripts",
        },
      },
      required: ["operation", "namespace"],
    },
  },
];

/**
 * Handler for listing available tools
 */
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools };
});

/**
 * Handler for tool execution
 */
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    switch (name) {
      case "deploy_vault_cluster":
        return await deployVaultCluster(args);
      
      case "manage_vault_config":
        return await manageVaultConfig(args);
      
      case "generate_certificates":
        return await generateCertificates(args);
      
      case "initialize_vault":
        return await initializeVault(args);
      
      case "troubleshoot_deployment":
        return await troubleshootDeployment(args);
      
      case "check_cluster_status":
        return await checkClusterStatus(args);
      
      case "manage_namespace_route":
        return await manageNamespaceRoute(args);
      
      default:
        throw new Error(`Unknown tool: ${name}`);
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text",
          text: `Error executing ${name}: ${errorMessage}`,
        },
      ],
      isError: true,
    };
  }
});

/**
 * Start the MCP server
 */
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Vault Cluster MCP Server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error in main():", error);
  process.exit(1);
});
