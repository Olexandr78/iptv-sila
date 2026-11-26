import { cp, mkdir } from 'node:fs/promises';
await mkdir('www', { recursive: true });
await cp('web', 'www', { recursive: true });
console.log('Web client copied to www/');
