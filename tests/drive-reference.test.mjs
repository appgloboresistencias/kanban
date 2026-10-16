import test from 'node:test';import assert from 'node:assert/strict';
import {driveFileId} from '../src/drive.ts';
test('referência de arquivo permite Drive e recusa destinos externos/pastas',()=>{
assert.equal(driveFileId('https://drive.google.com/file/d/0123456789abcdef/view?usp=sharing'),'0123456789abcdef');
assert.equal(driveFileId('https://drive.google.com/open?id=0123456789abcdef'),'0123456789abcdef');
for(const link of ['javascript:alert(1)','https://evil.test/file/d/0123456789/view','https://drive.google.com.evil.test/file/d/0123456789/view','https://drive.google.com/drive/folders/0123456789','https://user@drive.google.com/file/d/0123456789/view',''])assert.equal(driveFileId(link),null);
});
