/**
 * Directory Handle Persistence
 * 
 * The File System Access API allows persisting directory handles to IndexedDB.
 * This enables automatic restoration of the last opened directory on page reload.
 * 
 * Note: Browser still requires user permission verification on each page load,
 * but this avoids re-selecting the same folder repeatedly.
 */

import type { FileSystemDirectoryHandle } from './types';

const DB_NAME = 'TradeRoutesAnalyzer';
const DB_VERSION = 1;
const STORE_NAME = 'directoryHandles';
const HANDLE_KEY = 'lastDirectory';

/**
 * Open IndexedDB database
 */
function openDB(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(DB_NAME, DB_VERSION);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve(request.result);

    request.onupgradeneeded = (event) => {
      const db = (event.target as IDBOpenDBRequest).result;
      if (!db.objectStoreNames.contains(STORE_NAME)) {
        db.createObjectStore(STORE_NAME);
      }
    };
  });
}

/**
 * Save directory handle to IndexedDB
 */
export async function saveDirectoryHandle(handle: FileSystemDirectoryHandle): Promise<void> {
  const db = await openDB();
  
  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.put(handle, HANDLE_KEY);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve();
    transaction.oncomplete = () => db.close();
  });
}

/**
 * Load directory handle from IndexedDB
 * Returns null if no handle was saved or if permission was denied
 */
export async function loadDirectoryHandle(): Promise<FileSystemDirectoryHandle | null> {
  try {
    const db = await openDB();

    const handle = await new Promise<FileSystemDirectoryHandle | null>((resolve, reject) => {
      const transaction = db.transaction(STORE_NAME, 'readonly');
      const store = transaction.objectStore(STORE_NAME);
      const request = store.get(HANDLE_KEY);

      request.onerror = () => reject(request.error);
      request.onsuccess = () => resolve(request.result || null);
      transaction.oncomplete = () => db.close();
    });

    if (!handle) {
      return null;
    }

    // Verify we still have permission
    // Note: queryPermission/requestPermission may not be in all TypeScript definitions
    // but they are part of the File System Access API spec
    const handleWithPermissions = handle as FileSystemDirectoryHandle & {
      queryPermission(descriptor?: { mode?: 'read' | 'readwrite' }): Promise<PermissionState>;
      requestPermission(descriptor?: { mode?: 'read' | 'readwrite' }): Promise<PermissionState>;
    };

    const permission = await handleWithPermissions.queryPermission({ mode: 'read' });

    if (permission === 'granted') {
      return handle;
    }

    // Request permission again
    const newPermission = await handleWithPermissions.requestPermission({ mode: 'read' });

    if (newPermission === 'granted') {
      return handle;
    }

    // Permission denied
    return null;
  } catch (error) {
    console.warn('Failed to load directory handle:', error);
    return null;
  }
}

/**
 * Clear saved directory handle
 */
export async function clearDirectoryHandle(): Promise<void> {
  const db = await openDB();

  return new Promise((resolve, reject) => {
    const transaction = db.transaction(STORE_NAME, 'readwrite');
    const store = transaction.objectStore(STORE_NAME);
    const request = store.delete(HANDLE_KEY);

    request.onerror = () => reject(request.error);
    request.onsuccess = () => resolve();
    transaction.oncomplete = () => db.close();
  });
}

