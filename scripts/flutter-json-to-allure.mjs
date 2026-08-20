#!/usr/bin/env node
// Convert Flutter's host-side JSON reporter stream into minimal Allure result
// files. Device integration tests cannot write Allure files from the Android
// test process, but Flutter's JSON reporter remains on the host.

import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { basename, resolve } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';

const args = process.argv.slice(2);
const valueFor = (flag) => {
  const index = args.indexOf(flag);
  return index >= 0 ? args[index + 1] : undefined;
};

const inputPath = valueFor('--input');
const outputDir = valueFor('--output');
const version = valueFor('--version');

if (!inputPath || !outputDir || !version) {
  console.error('usage: flutter-json-to-allure.mjs --input <stream.json> --output <allure-results-dir> --version <scoreboard-version>');
  process.exit(2);
}

const tests = new Map();
const lines = (await readFile(inputPath, 'utf8')).split(/\r?\n/);
for (const line of lines) {
  if (!line.trim()) continue;
  let event;
  try {
    event = JSON.parse(line);
  } catch {
    continue;
  }

  if (event.type === 'testStart') {
    tests.set(event.test.id, {
      name: event.test.name,
      url: event.test.url,
      start: Date.now(),
      errors: [],
    });
  } else if (event.type === 'error' && tests.has(event.testID)) {
    tests.get(event.testID).errors.push({
      message: event.error ?? 'Flutter test failed',
      trace: event.stackTrace ?? '',
    });
  } else if (event.type === 'testDone' && tests.has(event.testID)) {
    const test = tests.get(event.testID);
    test.result = event.result;
    test.hidden = event.hidden;
    test.skipped = event.skipped;
    test.stop = Date.now();
  }
}

await mkdir(outputDir, { recursive: true });
for (const test of tests.values()) {
  if (!test.result || test.hidden) continue;
  const failure = test.errors.at(-1);
  const status = test.skipped || test.result === 'skipped'
    ? 'skipped'
    : test.result === 'success' || test.result === 'passed'
      ? 'passed'
      : 'failed';
  const fullName = `${version}: ${test.url ?? 'integration_test'}: ${test.name}`;
  const testId = createHash('md5').update(fullName).digest('hex');
  const result = {
    uuid: randomUUID(),
    name: test.name,
    fullName,
    historyId: testId,
    testCaseId: testId,
    status,
    stage: 'finished',
    start: test.start,
    stop: test.stop ?? test.start,
    labels: [
      { name: 'framework', value: 'flutter-integration-test' },
      { name: 'parentSuite', value: 'Scoreboard compatibility' },
      { name: 'suite', value: version },
      { name: 'subSuite', value: 'scoreboard_integration_test.dart' },
      { name: 'testClass', value: version },
      { name: 'testMethod', value: test.name },
    ],
    parameters: [
      { name: 'scoreboard_version', value: version },
    ],
  };
  if (failure) {
    result.statusDetails = {
      message: failure.message,
      trace: failure.trace,
    };
  }
  await writeFile(
    resolve(outputDir, `${randomUUID()}-result.json`),
    `${JSON.stringify(result)}\n`,
  );
}
