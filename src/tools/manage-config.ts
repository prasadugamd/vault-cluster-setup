import { readFile, writeFile, readdir } from "fs/promises";
import * as path from "path";

interface ManageVaultConfigArgs {
  operation: "read" | "create" | "update" | "validate" | "list";
  configFile?: string;
  updates?: Record<string, any>;
  template?: string;
  workingDirectory?: string;
}

export async function manageVaultConfig(args: any) {
  const {
    operation,
    configFile,
    updates,
    template,
    workingDirectory = process.cwd(),
  } = args as ManageVaultConfigArgs;

  try {
    switch (operation) {
      case "list":
        return await listConfigs(workingDirectory);
      
      case "read":
        if (!configFile) throw new Error("configFile is required for read operation");
        return await readConfig(configFile, workingDirectory);
      
      case "create":
        if (!configFile) throw new Error("configFile is required for create operation");
        return await createConfig(configFile, template, workingDirectory);
      
      case "update":
        if (!configFile) throw new Error("configFile is required for update operation");
        if (!updates) throw new Error("updates is required for update operation");
        return await updateConfig(configFile, updates, workingDirectory);
      
      case "validate":
        if (!configFile) throw new Error("configFile is required for validate operation");
        return await validateConfig(configFile, workingDirectory);
      
      default:
        throw new Error(`Unknown operation: ${operation}`);
    }
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    return {
      content: [
        {
          type: "text",
          text: `Configuration operation failed: ${errorMessage}`,
        },
      ],
      isError: true,
    };
  }
}

async function listConfigs(workingDir: string) {
  const files = await readdir(workingDir);
  const configFiles = files.filter(
    (f) => f.startsWith("config-") && f.endsWith(".json")
  );

  let response = `# Configuration Files\n\n`;
  response += `Found ${configFiles.length} configuration file(s):\n\n`;
  configFiles.forEach((file) => {
    response += `- ${file}\n`;
  });

  return {
    content: [{ type: "text", text: response }],
  };
}

async function readConfig(configFile: string, workingDir: string) {
  const filePath = path.join(workingDir, configFile);
  const content = await readFile(filePath, "utf-8");
  const config = JSON.parse(content);

  let response = `# Configuration: ${configFile}\n\n`;
  response += `\`\`\`json\n${JSON.stringify(config, null, 2)}\n\`\`\`\n`;

  return {
    content: [{ type: "text", text: response }],
  };
}

async function createConfig(configFile: string, template: string | undefined, workingDir: string) {
  const filePath = path.join(workingDir, configFile);
  
  let config: any;
  if (template) {
    const templatePath = path.join(workingDir, template);
    const templateContent = await readFile(templatePath, "utf-8");
    config = JSON.parse(templateContent);
  } else {
    // Use default template
    const examplePath = path.join(workingDir, "config.example.json");
    const exampleContent = await readFile(examplePath, "utf-8");
    config = JSON.parse(exampleContent);
  }

  await writeFile(filePath, JSON.stringify(config, null, 2));

  return {
    content: [
      {
        type: "text",
        text: `Created configuration file: ${configFile}\n\nPlease review and update the configuration before deployment.`,
      },
    ],
  };
}

async function updateConfig(
  configFile: string,
  updates: Record<string, any>,
  workingDir: string
) {
  const filePath = path.join(workingDir, configFile);
  const content = await readFile(filePath, "utf-8");
  const config = JSON.parse(content);

  // Apply updates
  Object.keys(updates).forEach((key) => {
    if (key.includes(".")) {
      // Handle nested keys like "vault.namespace"
      const parts = key.split(".");
      let current = config;
      for (let i = 0; i < parts.length - 1; i++) {
        if (!current[parts[i]]) current[parts[i]] = {};
        current = current[parts[i]];
      }
      current[parts[parts.length - 1]] = updates[key];
    } else {
      config[key] = updates[key];
    }
  });

  await writeFile(filePath, JSON.stringify(config, null, 2));

  let response = `# Configuration Updated: ${configFile}\n\n`;
  response += `**Updated fields:**\n`;
  Object.keys(updates).forEach((key) => {
    response += `- ${key}: ${JSON.stringify(updates[key])}\n`;
  });
  response += `\n**New configuration:**\n\n`;
  response += `\`\`\`json\n${JSON.stringify(config, null, 2)}\n\`\`\`\n`;

  return {
    content: [{ type: "text", text: response }],
  };
}

async function validateConfig(configFile: string, workingDir: string) {
  const filePath = path.join(workingDir, configFile);
  const content = await readFile(filePath, "utf-8");
  
  try {
    const config = JSON.parse(content);
    
    // Validate required fields
    const requiredFields = ["namespace", "releaseName"];
    const missing = requiredFields.filter((field) => !config[field]);
    
    if (missing.length > 0) {
      return {
        content: [
          {
            type: "text",
            text: `❌ Configuration validation failed\n\nMissing required fields: ${missing.join(", ")}`,
          },
        ],
        isError: true,
      };
    }

    return {
      content: [
        {
          type: "text",
          text: `✅ Configuration is valid\n\n**Namespace:** ${config.namespace}\n**Release Name:** ${config.releaseName}`,
        },
      ],
    };
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `❌ Invalid JSON in configuration file: ${error}`,
        },
      ],
      isError: true,
    };
  }
}
