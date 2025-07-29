import pkmn from "@pkmn/eslint-config";

export default [...pkmn, {
  files: ["src/bin/!(*.*)"],
}, {
  ignores: ["dist/", "node_modules/", "examples/zig", "build/", "src/tools/vscode/extension.js"],
}, {
  files: ["src/pkg/common.ts", "src/pkg/index.ts", "src/test/integration.ts"],
  rules: {
    "no-control-regex": "off",
    "@typescript-eslint/no-empty-interface": "off",
    "@typescript-eslint/no-shadow": "off",
    "@typescript-eslint/no-unsafe-declaration-merging": "off"
  }
}, {
  files: ["src/pkg/addon/node.ts", "src/tools/debug.ts"],
  rules: {
    "@typescript-eslint/no-var-requires": "off",
    "@typescript-eslint/no-require-imports": "off",
  }
},{
  files: ["src/test/benchmark*.ts"],
  rules: {
    "@typescript-eslint/no-unused-vars": "off",
    "@typescript-eslint/no-redundant-type-constituents": "off"
  }
}, {
  files: ["src/pkg/protocol.test.ts"],
  rules: {"jest/no-standalone-expect": "off", "jest/no-conditional-expect": "off"}
}, {
  files: ["src/test/*.test.ts"],
  rules: {"jest/no-standalone-expect": "off"}
}, {
  files: ["src/test/showdown/**"],
  rules: {"jest/expect-expect": ["warn", {assertFunctionNames: ["expect", "expectLog", "verify"]}]}
}, {
  files: ["src/test/fuzz.ts", "src/tools/serde.ts"],
  rules: {"@typescript-eslint/prefer-promise-reject-errors": "off"},
}, {
  files: ["src/tools/generate.ts"],
  rules: {"@typescript-eslint/restrict-template-expressions": ["error", {"allowBoolean": true}]}
}, {
  files: ["src/tools/display/debug.tsx"],
  rules: {"@stylistic/indent": "off"}
}];
