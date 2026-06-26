module.exports = {
  root: true,
  env: { es6: true, node: true },
  parser: "@typescript-eslint/parser",
  parserOptions: { ecmaVersion: 2020, sourceType: "module" },
  extends: ["eslint:recommended", "plugin:@typescript-eslint/recommended"],
  plugins: ["@typescript-eslint", "import"],
  ignorePatterns: ["lib/**", "node_modules/**", "*.test.ts", "jest.config.js", ".eslintrc.js"],
  rules: {
    "quotes": ["error", "double"],
    "max-len": ["error", { code: 110 }],
    "@typescript-eslint/no-explicit-any": "off",
  },
};
