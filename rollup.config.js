/* eslint-disable no-restricted-syntax */
import path from 'node:path';
import alias from '@rollup/plugin-alias';
import { nodeResolve } from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import vue from 'rollup-plugin-vue';

const isLibraryMode = process.env.BUILD_MODE === 'library';

// Note: only works for SCSS
const scssAliasMap = {
  shared: path.resolve(__dirname, 'app/javascript/shared'),
  components: path.resolve(__dirname, 'app/javascript/dashboard/components'),
  next: path.resolve(__dirname, 'app/javascript/dashboard/components-next'),
  v3: path.resolve(__dirname, 'app/javascript/v3'),
  dashboard: path.resolve(__dirname, 'app/javascript/dashboard'),
  helpers: path.resolve(__dirname, 'app/javascript/shared/helpers'),
  survey: path.resolve(__dirname, 'app/javascript/survey'),
  widget: path.resolve(__dirname, 'app/javascript/widget'),
  assets: path.resolve(__dirname, 'app/javascript/dashboard/assets'),
};

function scssAliasImporter(url) {
  for (const [aliasName, aliasPath] of Object.entries(scssAliasMap)) {
    if (url.startsWith(aliasName + '/')) {
      const subPath = url.slice(aliasName.length + 1);
      const resolvedPath = path.join(aliasPath, subPath);
      return { file: resolvedPath };
    }
  }

  return { file: url };
}

const vueOptions = {
  css: true,
  compileTemplate: true,
  preprocessStyles: true,
  preprocessOptions: {
    scss: {
      importer: scssAliasImporter,
    },
  },
  template: {
    compilerOptions: {
      isCustomElement: tag => ['ninja-keys'].includes(tag),
    },
  },
};

let plugins = [];
if (isLibraryMode) {
  plugins = [];
} else {
  plugins = [vue(vueOptions)];
}

plugins.push(
  // Note: only works for JS/TS, not for SCSS
  alias({
    entries: [
      { find: 'vue', replacement: 'vue/dist/vue.esm-bundler.js' },
      {
        find: 'components',
        replacement: path.resolve('./app/javascript/dashboard/components'),
      },
      {
        find: 'next',
        replacement: path.resolve('./app/javascript/dashboard/components-next'),
      },
      { find: 'v3', replacement: path.resolve('./app/javascript/v3') },
      {
        find: 'dashboard',
        replacement: path.resolve('./app/javascript/dashboard'),
      },
      {
        find: 'helpers',
        replacement: path.resolve('./app/javascript/shared/helpers'),
      },
      { find: 'shared', replacement: path.resolve('./app/javascript/shared') },
      { find: 'survey', replacement: path.resolve('./app/javascript/survey') },
      { find: 'widget', replacement: path.resolve('./app/javascript/widget') },
      {
        find: 'assets',
        replacement: path.resolve('./app/javascript/dashboard/assets'),
      },
    ],
  }),
  nodeResolve({
    extensions: ['.js', '.ts', '.vue'],
    browser: true,
  }),
  commonjs()
);

export default {
  input: isLibraryMode
    ? path.resolve(__dirname, './app/javascript/entrypoints/sdk.js')
    : {
        dashboard: path.resolve(
          __dirname,
          './app/javascript/entrypoints/dashboard.js'
        ),
        widget: path.resolve(
          __dirname,
          './app/javascript/entrypoints/widget.js'
        ),
      },

  output: isLibraryMode
    ? {
        dir: 'public/packs',
        entryFileNames: chunkInfo => {
          if (chunkInfo.name === 'sdk') {
            return 'js/sdk.js';
          }
          return '[name].js';
        },
        format: 'iife',
        name: 'sdk',
        inlineDynamicImports: true,
        sourcemap: true,
      }
    : {
        dir: 'dist',
        format: 'esm',
        entryFileNames: '[name].js',
        sourcemap: true,
      },

  plugins,
};
