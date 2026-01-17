#!/usr/bin/env node
/**
 * Standalone copy script for app-store static files.
 * Uses only Node.js built-in modules (no external dependencies like glob).
 * This is safe to run in production where devDependencies aren't installed.
 */

const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

/**
 * Recursively find all files matching a pattern in a directory
 */
function findStaticFiles(baseDir) {
    const results = [];

    if (!fs.existsSync(baseDir)) {
        console.log(`Base directory not found: ${baseDir}`);
        return results;
    }

    const entries = fs.readdirSync(baseDir, { withFileTypes: true });

    for (const entry of entries) {
        const fullPath = path.join(baseDir, entry.name);

        if (entry.isDirectory()) {
            // Check if this is a static directory
            if (entry.name === "static") {
                // Get all files in the static directory
                const staticFiles = getFilesRecursively(fullPath);
                staticFiles.forEach(file => {
                    results.push({
                        filePath: file,
                        appDirName: path.basename(path.dirname(path.dirname(file)))
                    });
                });
            } else {
                // Recurse into subdirectories
                results.push(...findStaticFiles(fullPath));
            }
        }
    }

    return results;
}

/**
 * Get all files recursively from a directory
 */
function getFilesRecursively(dir) {
    const results = [];

    if (!fs.existsSync(dir)) return results;

    const entries = fs.readdirSync(dir, { withFileTypes: true });

    for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isDirectory()) {
            results.push(...getFilesRecursively(fullPath));
        } else {
            results.push(fullPath);
        }
    }

    return results;
}

function copyAppStoreStatic() {
    // Determine the base path for app-store packages
    const appStorePath = path.resolve(__dirname, "../../../packages/app-store");
    const publicAppStorePath = path.resolve(__dirname, "../public/app-store");

    console.log(`Scanning: ${appStorePath}`);
    console.log(`Output: ${publicAppStorePath}`);

    // Ensure the output directory exists
    if (!fs.existsSync(publicAppStorePath)) {
        fs.mkdirSync(publicAppStorePath, { recursive: true });
    }

    // Find all static files
    const staticFiles = findStaticFiles(appStorePath);

    if (staticFiles.length === 0) {
        console.log("No static files found!");
        return;
    }

    // Object to store icon SVG hashes
    const SVG_HASHES = {};
    let copiedCount = 0;

    staticFiles.forEach(({ filePath, appDirName }) => {
        const fileName = path.basename(filePath);

        // Create destination directory if it doesn't exist
        const destDir = path.join(publicAppStorePath, appDirName);
        if (!fs.existsSync(destDir)) {
            fs.mkdirSync(destDir, { recursive: true });
        }

        // Copy file to destination
        const destPath = path.join(destDir, fileName);
        fs.copyFileSync(filePath, destPath);
        copiedCount++;

        // If it's an icon SVG file, compute hash
        if (fileName.includes("icon") && fileName.endsWith(".svg")) {
            const content = fs.readFileSync(filePath, "utf8");
            const hash = crypto.createHash("md5").update(content).digest("hex").slice(0, 8);
            SVG_HASHES[appDirName] = hash;
        }

        console.log(`Copied ${appDirName}/${fileName}`);
    });

    // Write SVG hashes to a JSON file
    const hashFilePath = path.join(publicAppStorePath, "svg-hashes.json");
    fs.writeFileSync(hashFilePath, JSON.stringify(SVG_HASHES, null, 2));

    console.log(`\nDone! Copied ${copiedCount} files.`);
    console.log(`SVG hashes written to ${hashFilePath}`);
}

// Run the copy function
copyAppStoreStatic();
