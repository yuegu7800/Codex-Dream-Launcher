import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import path from 'node:path';
import os from 'node:os';
import {loadPayload, setStreamCspBypass} from '../engine/scripts/injector.mjs';

let calls = 0;
await assert.rejects(setStreamCspBypass({send: async () => { calls++; }}, true), /CSP bypass is disabled/);
assert.equal(calls, 0, 'A rejected scene request must not reach CDP');
const fixture = await fs.mkdtemp(path.join(os.tmpdir(), 'dragon-theme-test-'));
try {
  for (const [image, media] of [
    ['wallpaper.mp4', {type:'scene', streamUrl:'http://127.0.0.1:1234/stream.mp4'}],
    ['wallpaper.mp4', {type:'video', streamUrl:'http://127.0.0.1:1234/stream.mp4'}],
    ['wallpaper.webm', {type:'video'}],
  ]) {
    const theme = JSON.parse(await fs.readFile(new URL('../themes/dragon/theme.json', import.meta.url), 'utf8'));
    Object.assign(theme, {image, media});
    await fs.writeFile(path.join(fixture, 'theme.json'), JSON.stringify(theme));
    await assert.rejects(loadPayload(fixture), /only supports local MP4/);
  }
} finally { await fs.rm(fixture, {recursive:true, force:true}); }
console.log('PASS: CSP bypass rejected before CDP; scene, stream and non-MP4 themes rejected.');
