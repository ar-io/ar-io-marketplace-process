import fs from 'fs';
import path from 'path';
import chalk from 'chalk';
import Table from 'cli-table3';

/**
 * @typedef Module
 * @property {string} name
 * @property {string} path
 * @property {string|undefined} content
 */

interface CircularDependency {
  from: string;
  to: string;
  path: string[];
  fromLine?: number;
}

/**
 * @param {Module[]} project
 * @returns {[string, Module[]]}
 */
function createExecutableFromProject(project) {
  const getModFnName = (name) => name.replace(/\./g, '_').replace(/^_/, '');
  /** @type {Module[]} */
  const contents: any[] = [];

  // filter out repeated modules with different import names
  // and construct the executable Lua code
  // (the main file content is handled separately)
  for (let i = 0; i < project.length - 1; i++) {
    const mod = project[i];

    const existing = contents.find((m) => m.path === mod.path);
    const moduleContent =
      (!existing &&
        `-- module: "${mod.name}"\nlocal function _loaded_mod_${getModFnName(mod.name)}()\n${mod.content}\nend\n`) ||
      '';
    const requireMapper = `\n_G.package.loaded["${mod.name}"] = _loaded_mod_${getModFnName(existing?.name || mod.name)}()`;

    contents.push({
      ...mod,
      content: moduleContent + requireMapper,
    });
  }

  // finally, add the main file
  contents.push(project[project.length - 1]);

  return [
    contents.reduce((acc, con) => acc + '\n\n' + con.content, ''),
    contents,
  ];
}

/**
 * Create the project structure from the main file's content
 * @param {string} mainFile
 * @return {Module[]}
 */
function createProjectStructure(mainFile) {
  const sorted: any[] = [];
  const cwd = path.dirname(mainFile);
  const visiting = new Set<string>(); // Track nodes currently in DFS path
  const visited = new Set<string>(); // Track nodes that are fully processed
  const circularDeps: CircularDependency[] = [];
  const visitPath: string[] = []; // Track current DFS path for circular dependency reporting

  // checks if the sorted module list already includes a node
  const isSorted = (node) =>
    sorted.find((sortedNode: any) => sortedNode.path === node.path);

  // recursive dfs algorithm with circular dependency detection
  function dfs(currentNode) {
    // Skip if already fully processed
    if (visited.has(currentNode.path)) {
      return;
    }

    // Detect circular dependency
    if (visiting.has(currentNode.path)) {
      const cyclePath = [...visitPath];
      const cycleStart = cyclePath.indexOf(currentNode.path);
      const cycle = cyclePath
        .slice(cycleStart)
        .map((p) => path.basename(p, '.lua'));

      circularDeps.push({
        from: cyclePath[cyclePath.length - 1],
        to: currentNode.path,
        path: [...cycle, path.basename(currentNode.path, '.lua')],
        fromLine: currentNode.lineNumber,
      });
      return; // Break the cycle
    }

    // Mark as visiting and add to path
    visiting.add(currentNode.path);
    visitPath.push(currentNode.path);

    const childNodes = exploreNodes(currentNode, cwd);
    const unvisitedChildNodes = childNodes.filter(
      (node: any) => !visited.has(node.path),
    );

    for (let i = 0; i < unvisitedChildNodes.length; i++) {
      dfs(unvisitedChildNodes[i]);
    }

    // Mark as done visiting
    visiting.delete(currentNode.path);
    visitPath.pop();
    visited.add(currentNode.path);

    if (!isSorted(currentNode)) sorted.push(currentNode);
  }

  // run DFS from the main file
  dfs({ path: mainFile });

  // Display circular dependencies warning if any found
  if (circularDeps.length > 0) {
    // Separate self-references from other circular dependencies
    const selfReferences: CircularDependency[] = [];
    const otherCircularDeps: CircularDependency[] = [];

    // Group by unique circular paths to avoid duplicates
    const uniqueDeps = circularDeps.reduce((acc, dep) => {
      const key = `${dep.from}:${dep.to}`;
      if (!acc.has(key)) {
        acc.set(key, dep);
      }
      return acc;
    }, new Map());

    // Categorize dependencies
    for (const dep of uniqueDeps.values()) {
      if (dep.from === dep.to) {
        selfReferences.push(dep);
      } else {
        otherCircularDeps.push(dep);
      }
    }

    // Display self-references with special message
    if (selfReferences.length > 0) {
      console.log('\n' + chalk.magenta.bold('⚠️  Self-References Detected:'));

      for (const dep of selfReferences) {
        const fromFile = dep.from;
        const lineInfo = dep.fromLine ? `:${dep.fromLine}:1` : '';
        const clickablePath = chalk.cyan.underline(`${fromFile}${lineInfo}`);

        console.log(`  ${chalk.magenta('⟲')} ${clickablePath}`);
        console.log(
          `    ${chalk.dim('requires itself')} ${chalk.magenta(path.basename(dep.to, '.lua'))}\n`,
        );
      }

      console.log(
        chalk.dim(
          '💡 Note: Self-references are often used for dynamic reloading or hot-module replacement.',
        ),
      );
      console.log(
        chalk.dim(
          '   This pattern is intentional for runtime module updates but should be used sparingly.\n',
        ),
      );
    }

    // Display other circular dependencies
    if (otherCircularDeps.length > 0) {
      console.log(
        '\n' + chalk.yellow.bold('⚠️  Circular Dependencies Detected:'),
      );

      for (const dep of otherCircularDeps) {
        const fromFile = dep.from;
        const lineInfo = dep.fromLine ? `:${dep.fromLine}:1` : '';
        const clickablePath = chalk.cyan.underline(`${fromFile}${lineInfo}`);

        console.log(`  ${chalk.yellow('→')} ${clickablePath}`);
        console.log(
          `    ${chalk.dim('requires')} ${chalk.yellow(path.basename(dep.to, '.lua'))}`,
        );
        console.log(
          `    ${chalk.dim('cycle:')} ${chalk.dim(dep.path.join(' → '))}\n`,
        );
      }

      console.log(
        chalk.dim(
          '💡 Tip: Circular dependencies are handled by breaking the cycle.',
        ),
      );
      console.log(
        chalk.dim(
          '   Consider refactoring to extract shared logic into a separate module.\n',
        ),
      );
    }
  }

  return sorted.filter(
    // modules that were not read don't exist locally
    // aos assumes that these modules have already been
    // loaded into the process, or they're default modules
    (mod) => mod.content !== undefined,
  );
}

/**
 * Check if a position in a line is inside a comment
 * @param {string} line The line to check
 * @param {number} position The position in the line
 * @return {boolean}
 */
function isInComment(line: string, position: number): boolean {
  // Check for single-line comment
  const singleLineCommentIndex = line.indexOf('--');
  if (singleLineCommentIndex !== -1 && singleLineCommentIndex < position) {
    return true;
  }
  return false;
}

/**
 * Find child nodes for a node (a module) and track line numbers
 * @param {Module} node Parent node
 * @param {string} cwd Project root dir
 * @return {Module[]}
 */
function exploreNodes(node, cwd) {
  if (!fs.existsSync(node.path)) return [];

  // set content
  node.content = fs.readFileSync(node.path, 'utf-8');

  const requirePattern = /require\s*\(\s*['"]([^'"]+)['"]\s*\)/g;
  const lines = node.content.split('\n');
  const requiredModules: any[] = [];

  // Track if we're inside a multi-line comment
  let inMultiLineComment = false;

  // Track line numbers for each require
  lines.forEach((line, lineIndex) => {
    // Check for multi-line comment start/end
    if (line.includes('--[[')) {
      inMultiLineComment = true;
    }
    if (line.includes(']]')) {
      inMultiLineComment = false;
      return; // Skip this line
    }

    // Skip if in multi-line comment
    if (inMultiLineComment) {
      return;
    }

    // Reset regex lastIndex for each line
    requirePattern.lastIndex = 0;

    let match;
    while ((match = requirePattern.exec(line)) !== null) {
      const position = match.index;

      // Skip if this require is in a single-line comment
      if (isInComment(line, position)) {
        continue;
      }

      const moduleName = match[1];
      if (moduleName) {
        requiredModules.push({
          name: moduleName,
          path: path.join(cwd, moduleName.replace(/\./g, '/') + '.lua'),
          content: undefined,
          lineNumber: lineIndex + 1, // 1-based line numbers
        });
      }
    }
  });

  return requiredModules;
}

export function bundle(entryLuaPath) {
  console.log(chalk.blue('🔍 Analyzing module dependencies...\n'));

  const project = createProjectStructure(entryLuaPath);

  console.log(chalk.green(`✓ Found ${project.length} modules to bundle\n`));

  const [bundledLua] = createExecutableFromProject(project);

  return bundledLua;
}
