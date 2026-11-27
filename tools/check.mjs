// Checks template.tpl without Tag Manager: section syntax, sandbox lint, permissions against the APIs in
// use, and the ___TESTS___ scenarios on a small stand-in for the template test runner. The real runner is the
// Tests tab of the template editor; this one only knows the APIs listed below.
import { readFileSync } from 'node:fs';
import { isDeepStrictEqual } from 'node:util';

const file = process.argv[2] ?? new URL('../template.tpl', import.meta.url);
// An editor export may start with a byte order mark, which would hide the first section header.
const text = readFileSync(file, 'utf8').replace(/^\uFEFF/, '');
const errors = [];
const check = (ok, msg) => ok || errors.push(msg);

const sections = {};
for (const part of text.split(/^(?=___[A-Z_]+___$)/m)) {
  const name = /^___([A-Z_]+)___\n/.exec(part);
  if (name) sections[name[1]] = part.slice(name[0].length).trim();
}
const need = ['INFO', 'TEMPLATE_PARAMETERS', 'SANDBOXED_JS_FOR_WEB_TEMPLATE', 'WEB_PERMISSIONS', 'TESTS'];
for (const n of need) check(sections[n], `missing section ${n}`);
if (errors.length) done();

const json = (n) => {
  try {
    return JSON.parse(sections[n]);
  } catch (e) {
    errors.push(`${n}: ${e.message}`);
    done();
  }
};
const info = json('INFO');
const params = json('TEMPLATE_PARAMETERS');
const perms = json('WEB_PERMISSIONS');
const code = sections.SANDBOXED_JS_FOR_WEB_TEMPLATE;

check(info.type === 'TAG' && info.containerContexts?.includes('WEB'), 'INFO: a web tag is expected');
// Literal or as a JSON escape; spelled so that this file passes the same grep.
const dashes = [8211, 8212].flatMap((c) => [String.fromCharCode(c), '\\u' + c.toString(16)]);
check(!dashes.some((d) => text.includes(d)), 'en or em dash in the file');

// Field names the code reads must exist, and the other way round.
const fields = [];
(function walk(list) {
  for (const p of list) {
    if (!['GROUP', 'LABEL'].includes(p.type)) fields.push(p.name);
    walk(p.subParams ?? []);
  }
})(params);
const used = [...code.matchAll(/\bdata\.(\w+)/g)].map((m) => m[1]).filter((n) => !n.startsWith('gtmOn'));
for (const n of new Set(used)) check(fields.includes(n), `code reads data.${n}, no such field`);
for (const n of fields) check(used.includes(n), `field ${n} is never read`);

// Sandboxed JavaScript: ES5.1 with const, let and arrows; no globals, no new, no this, no regular expressions,
// and only the methods of its standard library. A list of known traps, not a parser: the editor has the last word.
// https://developers.google.com/tag-platform/tag-manager/templates/sandboxed-javascript
// https://developers.google.com/tag-platform/tag-manager/templates/standard-library
const strip = (js) => js.replace(/'(?:[^'\\\n]|\\.)*'|\/\/.*$/gm, (m) => (m[0] === "'" ? "''" : ''));
const METHODS = new Set(
  ('charAt concat indexOf lastIndexOf match replace search slice split substring toLowerCase toUpperCase trim toString ' +
    'every filter forEach join map pop push reduce reduceRight reverse shift some sort splice unshift ' +
    'gtmOnSuccess gtmOnFailure').split(' '),
);
const banned = {
  'new': /\bnew\s/,
  'this': /\bthis\b/,
  'a global': /\b(window|document|location|navigator|setTimeout|Date|RegExp|Math|JSON|Object|Array|Number|String|console)\b/,
  'a regular expression': /(^|[=(,:!&|?])\s*\/[^/*\s]/m,
  'a template literal': /`/,
  'spread or rest': /\.\.\./,
  'a class': /\bclass\b/,
  'async code': /\b(async|await)\b/,
  'for...of': /\bfor\s*\(.*\bof\b/,
  'nullish coalescing': /\?\?/,
  'optional chaining': /\?\.(?!\d)/,
  'destructuring': /\b(const|let|var)\s*[[{]/,
};
const lint = (js, where) => {
  for (const [what, re] of Object.entries(banned)) check(!re.test(strip(js)), `sandbox lint, ${where}: ${what}`);
};
lint(code, 'code');
for (const [, m] of strip(code).matchAll(/\.(\w+)\(/g)) check(METHODS.has(m), `sandbox lint, code: .${m}() is not in the standard library`);

// Every API needs its permission, and no permission is left without an API.
const PERMISSION = {
  setDefaultConsentState: 'access_consent',
  updateConsentState: 'access_consent',
  gtagSet: 'write_data_layer',
  injectScript: 'inject_script',
  copyFromWindow: 'access_globals',
  setInWindow: 'access_globals',
  createQueue: 'access_globals',
  getCookieValues: 'get_cookies',
  logToConsole: 'logging',
};
const FREE = ['getTimestampMillis', 'makeInteger', 'makeString'];
const apis = [...code.matchAll(/require\('(\w+)'\)/g)].map((m) => m[1]);
const granted = Object.fromEntries(perms.map((p) => [p.instance.key.publicId, p.instance.param]));
const plain = (v) =>
  v.type === 2 ? v.listItem.map(plain)
  : v.type === 3 ? Object.fromEntries(v.mapKey.map((k, i) => [plain(k), plain(v.mapValue[i])]))
  : v.string ?? v.boolean;
const param = (id, key) => plain(granted[id]?.find((p) => p.key === key)?.value ?? { string: '' });
for (const a of apis) check(FREE.includes(a) || granted[PERMISSION[a]], `${a}: unknown API or missing permission`);
for (const id of Object.keys(granted)) check(apis.some((a) => PERMISSION[a] === id), `permission ${id} is not needed`);

const literal = (name) => new RegExp(`const ${name} = \\[?([^;]+);`).exec(code)?.[1].match(/'[^']+'/g)?.map((s) => s.slice(1, -1)) ?? [];
const urls = param('inject_script', 'urls');
check(isDeepStrictEqual(urls, literal('LOADER')), `inject_script allows ${urls}, the code loads ${literal('LOADER')}`);
check(urls.every((u) => u.startsWith('https://cdn.cookitap.pl/')), 'inject_script: not our host');
const writable = param('access_consent', 'consentTypes').filter((t) => t.write).map((t) => t.consentType);
for (const t of [...literal('TYPES'), 'wait_for_update']) check(writable.includes(t), `access_consent: no write for ${t}`);
const globals = Object.fromEntries(param('access_globals', 'keys').map((k) => [k.key, k]));
const access = { copyFromWindow: ['read'], setInWindow: ['write'], createQueue: ['read', 'write'] };
const touched = new Set();
for (const [, api, key] of code.matchAll(/\b(copyFromWindow|setInWindow|createQueue)\('([\w.]+)'/g)) {
  touched.add(key);
  for (const a of access[api]) check(globals[key]?.[a], `access_globals: ${api}('${key}') has no ${a} access`);
}
for (const k of Object.keys(globals)) check(touched.has(k), `access_globals: ${k} is not used`);
for (const k of param('write_data_layer', 'keyPatterns')) check(code.includes(`gtagSet({${k}:`), `write_data_layer: ${k} is not used`);

// ___TESTS___ is YAML in the one shape the editor exports: `- name:` with a `code: |-` block, then `setup: |-`.
const block = (src, indent) =>
  src.split('\n').map((l) => l.slice(indent)).join('\n');
const tests = sections.TESTS;
const setup = block(/^setup: \|-\n([\s\S]*)$/m.exec(tests)?.[1] ?? '', 2);
const scenarios = [...tests.matchAll(/^- name: (.*)\n  code: \|-\n((?: {4}.*\n|\n)*)/gm)].map((m) => ({ name: m[1], code: block(m[2], 4) }));
check(scenarios.length === (tests.match(/^- name:/gm) ?? []).length && scenarios.length > 0, 'TESTS: a scenario did not parse');
lint(setup, 'test setup');
for (const s of scenarios) lint(s.code, `test "${s.name}"`);

const builtin = {
  getTimestampMillis: () => Date.now(),
  makeInteger: (v) => parseInt(v, 10),
  makeString: (v) => String(v),
};
let failed = 0;
for (const s of scenarios) {
  const mocks = {};
  const calls = {};
  const api = (name) => (...args) => {
    (calls[name] ??= []).push(args);
    return (mocks[name] ?? builtin[name] ?? (() => undefined))(...args);
  };
  const env = {
    runCode: (data) => Function('require', 'data', code)(api, { ...data, gtmOnSuccess: api('gtmOnSuccess'), gtmOnFailure: api('gtmOnFailure') }),
    mock: (name, v) => (mocks[name] = typeof v == 'function' ? v : () => v),
    fail: (msg) => {
      throw Error(msg);
    },
    assertApi: (name) => {
      const got = calls[name] ?? [];
      const withArgs = (args) => got.some((c) => isDeepStrictEqual(c, args));
      const must = (ok, what) => ok || env.fail(`${name} ${what}; calls: ${JSON.stringify(got)}`);
      return {
        wasCalled: () => must(got.length, 'was not called'),
        wasNotCalled: () => must(!got.length, 'was called'),
        wasCalledWith: (...args) => must(withArgs(args), `was not called with ${JSON.stringify(args)}`),
        wasNotCalledWith: (...args) => must(!withArgs(args), `was called with ${JSON.stringify(args)}`),
      };
    },
    assertThat: (x, msg) => {
      const must = (ok, what) => ok || env.fail(`${msg ?? JSON.stringify(x)} ${what}`);
      return {
        isEqualTo: (y) => must(isDeepStrictEqual(x, y), `is not ${JSON.stringify(y)}`),
        isUndefined: () => must(x === undefined, 'is defined'),
        isDefined: () => must(x !== undefined, 'is undefined'),
      };
    },
  };
  try {
    Function(...Object.keys(env), `${setup}\n${s.code}`)(...Object.values(env));
    console.log(`ok    ${s.name}`);
  } catch (e) {
    failed++;
    console.log(`FAIL  ${s.name}\n      ${e.message}`);
  }
}
check(!failed, `${failed} of ${scenarios.length} test scenarios failed`);
done();

function done() {
  for (const e of errors) console.error(`error: ${e}`);
  console.log(errors.length ? 'check failed' : `check passed: ${Object.keys(sections).length} sections, ${fields.length} fields, ${scenarios.length} scenarios`);
  process.exit(errors.length ? 1 : 0);
}
