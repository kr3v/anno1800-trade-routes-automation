/**
 * File System Access API wrapper
 * Provides utilities for reading files and directories from the local filesystem
 */

import type { FileSystemDirectoryHandle, FileSystemFileHandle } from './types';

export * from './types';
export * from './directory-persistence';
export * from './result';

import { Ok, Err, type Result, FileNotFoundError, DirectoryNotFoundError, FileReadError, JsonParseError } from './result';

/**
 * Check if File System Access API is supported
 */
export function isFileSystemAccessSupported(): boolean {
  return 'showDirectoryPicker' in window && 'showOpenFilePicker' in window;
}

/**
 * Show directory picker dialog
 */
export async function pickDirectory(): Promise<FileSystemDirectoryHandle> {
  if (!isFileSystemAccessSupported()) {
    throw new Error('File System Access API is not supported in this browser. Please use Chrome or Edge.');
  }
  return window.showDirectoryPicker({ mode: 'read' });
}

/**
 * Show file picker dialog
 */
export async function pickFile(accept?: Record<string, string[]>): Promise<FileSystemFileHandle> {
  if (!isFileSystemAccessSupported()) {
    throw new Error('File System Access API is not supported in this browser. Please use Chrome or Edge.');
  }
  const [handle] = await window.showOpenFilePicker({
    multiple: false,
    types: accept ? [{ accept }] : undefined,
  });
  return handle;
}

/**
 * Read a file as text
 */
export async function readFileAsText(handle: FileSystemFileHandle): Promise<string> {
  const file = await handle.getFile();
  return file.text();
}

/**
 * Read a file as JSON
 */
export async function readFileAsJson<T>(handle: FileSystemFileHandle): Promise<T> {
  const text = await readFileAsText(handle);
  return JSON.parse(text) as T;
}

/**
 * Get a file handle from a directory, returns null if not found
 */
export async function getFileFromDirectory(
  dirHandle: FileSystemDirectoryHandle,
  path: string
): Promise<FileSystemFileHandle | null> {
  const parts = path.split('/').filter(Boolean);

  let current: FileSystemDirectoryHandle = dirHandle;

  // Navigate to subdirectories
  for (let i = 0; i < parts.length - 1; i++) {
    try {
      current = await current.getDirectoryHandle(parts[i]);
    } catch {
      return null;
    }
  }

  // Get the file
  const fileName = parts[parts.length - 1];
  try {
    return await current.getFileHandle(fileName);
  } catch {
    return null;
  }
}

/**
 * Get a subdirectory handle from a directory, returns null if not found
 */
export async function getSubdirectory(
  dirHandle: FileSystemDirectoryHandle,
  path: string
): Promise<FileSystemDirectoryHandle | null> {
  const parts = path.split('/').filter(Boolean);

  let current: FileSystemDirectoryHandle = dirHandle;

  for (const part of parts) {
    try {
      current = await current.getDirectoryHandle(part);
    } catch {
      return null;
    }
  }

  return current;
}

/**
 * List files in a directory matching a pattern
 */
export async function listFiles(
  dirHandle: FileSystemDirectoryHandle,
  pattern?: RegExp
): Promise<FileSystemFileHandle[]> {
  const files: FileSystemFileHandle[] = [];

  for await (const entry of dirHandle.values()) {
    if (entry.kind === 'file') {
      if (!pattern || pattern.test(entry.name)) {
        files.push(entry as FileSystemFileHandle);
      }
    }
  }

  return files;
}

/**
 * List subdirectories in a directory
 */
export async function listDirectories(
  dirHandle: FileSystemDirectoryHandle
): Promise<FileSystemDirectoryHandle[]> {
  const dirs: FileSystemDirectoryHandle[] = [];

  for await (const entry of dirHandle.values()) {
    if (entry.kind === 'directory') {
      dirs.push(entry as FileSystemDirectoryHandle);
    }
  }

  return dirs;
}

/**
 * Read JSON file from directory path
 */
export async function readJsonFromDirectory<T>(
  dirHandle: FileSystemDirectoryHandle,
  path: string
): Promise<T | null> {
  const fileHandle = await getFileFromDirectory(dirHandle, path);
  if (!fileHandle) return null;
  return readFileAsJson<T>(fileHandle);
}

/**
 * Read text file from directory path
 */
export async function readTextFromDirectory(
  dirHandle: FileSystemDirectoryHandle,
  path: string
): Promise<string | null> {
  const fileHandle = await getFileFromDirectory(dirHandle, path);
  if (!fileHandle) return null;
  return readFileAsText(fileHandle);
}

/**
 * Read a file as text (Result version)
 */
export async function readFileAsTextResult(
  handle: FileSystemFileHandle
): Promise<Result<string, FileReadError>> {
  try {
    const file = await handle.getFile();
    const text = await file.text();
    return Ok(text);
  } catch (error) {
    return Err(new FileReadError(handle.name, 'Failed to read file content', error));
  }
}

/**
 * Read a file as JSON (Result version)
 */
export async function readFileAsJsonResult<T>(
  handle: FileSystemFileHandle
): Promise<Result<T, FileReadError | JsonParseError>> {
  const textResult = await readFileAsTextResult(handle);
  if (!textResult.ok) {
    return textResult;
  }

  try {
    const parsed = JSON.parse(textResult.value) as T;
    return Ok(parsed);
  } catch (error) {
    return Err(new JsonParseError(handle.name, error));
  }
}

/**
 * Get a file handle from a directory (Result version)
 */
export async function getFileFromDirectoryResult(
  dirHandle: FileSystemDirectoryHandle,
  path: string
): Promise<Result<FileSystemFileHandle, FileNotFoundError | DirectoryNotFoundError>> {
  const parts = path.split('/').filter(Boolean);
  let current: FileSystemDirectoryHandle = dirHandle;

  // Navigate to subdirectories
  for (let i = 0; i < parts.length - 1; i++) {
    try {
      current = await current.getDirectoryHandle(parts[i]);
    } catch (error) {
      const subpath = parts.slice(0, i + 1).join('/');
      return Err(new DirectoryNotFoundError(subpath, error));
    }
  }

  // Get the file
  const fileName = parts[parts.length - 1];
  try {
    const handle = await current.getFileHandle(fileName);
    return Ok(handle);
  } catch (error) {
    return Err(new FileNotFoundError(path, error));
  }
}

/**
 * Read JSON file from directory path (Result version)
 */
export async function readJsonFromDirectoryResult<T>(
  dirHandle: FileSystemDirectoryHandle,
  path: string
): Promise<Result<T, FileNotFoundError | DirectoryNotFoundError | FileReadError | JsonParseError>> {
  const fileResult = await getFileFromDirectoryResult(dirHandle, path);
  if (!fileResult.ok) {
    return fileResult;
  }

  return readFileAsJsonResult<T>(fileResult.value);
}

