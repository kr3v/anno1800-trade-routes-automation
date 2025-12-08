/**
 * Result type for error handling
 * Similar to Rust's Result<T, E> or Go's (T, error) pattern
 */

/**
 * Result type representing either success with a value or failure with an error
 */
export type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E };

/**
 * Create a success result
 */
export function Ok<T>(value: T): Result<T, never> {
  return { ok: true, value };
}

/**
 * Create an error result
 */
export function Err<E = Error>(error: E): Result<never, E> {
  return { ok: false, error };
}

/**
 * Custom error types for file operations
 */
export class FileSystemError extends Error {
  constructor(message: string, public cause?: unknown) {
    super(message);
    this.name = 'FileSystemError';
  }
}

export class FileNotFoundError extends FileSystemError {
  constructor(public path: string, cause?: unknown) {
    super(`File not found: ${path}`, cause);
    this.name = 'FileNotFoundError';
  }
}

export class DirectoryNotFoundError extends FileSystemError {
  constructor(public path: string, cause?: unknown) {
    super(`Directory not found: ${path}`, cause);
    this.name = 'DirectoryNotFoundError';
  }
}

export class FileReadError extends FileSystemError {
  constructor(public path: string, message: string, cause?: unknown) {
    super(`Failed to read ${path}: ${message}`, cause);
    this.name = 'FileReadError';
  }
}

export class JsonParseError extends FileSystemError {
  constructor(public path: string, cause?: unknown) {
    super(`Failed to parse JSON from ${path}`, cause);
    this.name = 'JsonParseError';
  }
}

