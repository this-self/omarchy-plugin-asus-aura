const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '../..');

// QML JS libraries are ordinary ECMAScript with one QML-specific directive.
// Load the complete module, never extract functions from QML source text.
exports.load = file => {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(path.join(root, file), 'utf8').replace(/^\.pragma library\s*/, ''), context, {filename: file});
  return context;
};
exports.plain = value => JSON.parse(JSON.stringify(value));
exports.fixture = () => JSON.parse(fs.readFileSync(path.join(root, 'tests/fixtures/pre2021-global.json'), 'utf8'));
