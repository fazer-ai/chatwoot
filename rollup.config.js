import path from 'node:path';
import alias from '@rollup/plugin-alias';
import { nodeResolve } from '@rollup/plugin-node-resolve';
import commonjs from '@rollup/plugin-commonjs';
import vue from 'rollup-plugin-vue';
import postcss from 'rollup-plugin-postcss';
import replace from '@rollup/plugin-replace';
import terser from '@rollup/plugin-terser';
import json from '@rollup/plugin-json';
import url from '@rollup/plugin-url';
import serve from 'rollup-plugin-serve';
import livereload from 'rollup-plugin-livereload';

const isLibraryMode = process.env.BUILD_MODE === 'library';
const production = !process.env.ROLLUP_WATCH;

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

function scssAliasImporter(urlValue) {
  const entry = Object.entries(scssAliasMap).find(([aliasName]) =>
    urlValue.startsWith(aliasName + '/')
  );

  if (entry) {
    const [aliasName, aliasPath] = entry;
    const subPath = urlValue.slice(aliasName.length + 1);
    const resolvedPath = path.join(aliasPath, subPath);
    return { file: resolvedPath };
  }
  return { file: urlValue };
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
  include: /\.vue$/,
  target: 'browser',
  exposeFilename: false,
};

let plugins = [
  vue(vueOptions),
  url({
    include: ['**/*.png', '**/*.jpg', '**/*.gif', '**/*.svg'],
    limit: 0,
    fileName: '[name][extname]',
    publicPath: '/packs/js/',
  }),
  json(),
  postcss({
    extract: 'bundle.css',
    minimize: production,
  }),
  alias({
    entries: [
      { find: 'vue', replacement: 'vue/dist/vue.esm-bundler.js' },
      {
        find: '@lk77/vue3-color',
        replacement: require.resolve('@lk77/vue3-color'),
      },
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
      {
        find: 'punycode',
        replacement: path.resolve('./node_modules/punycode/punycode.js'),
      },
    ],
  }),
  replace({
    preventAssignment: true,
    values: {
      'process.env.NODE_ENV': JSON.stringify(
        production ? 'production' : 'development'
      ),
      'import.meta.env.DEV': JSON.stringify(!production),
      'import.meta.env.PROD': JSON.stringify(production),
      'import.meta.env.MODE': JSON.stringify(
        production ? 'production' : 'development'
      ),
    },
  }),
  commonjs({
    include: [/node_modules/, /\.vue\.js$/],
    transformMixedEsModules: true,
    ignoreDynamicRequires: true,
    requireReturnsDefault: 'preferred',
  }),
  nodeResolve({
    extensions: ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json', '.vue'],
    browser: true,
    preferBuiltins: false,
    dedupe: ['vue'],
  }),
  !production &&
    serve({
      contentBase: ['public'],
      port: 3036,
      historyApiFallback: true,
      headers: {
        'Access-Control-Allow-Origin': '*',
      },
    }),
  !production &&
    livereload({
      watch: 'public/packs',
      verbose: false,
    }),
  production && terser(),
].filter(Boolean);

const entrypoints = {
  dashboard: path.resolve(
    __dirname,
    './app/javascript/entrypoints/dashboard.js'
  ),
  widget: path.resolve(__dirname, './app/javascript/entrypoints/widget.js'),
  v3app: path.resolve(__dirname, './app/javascript/entrypoints/v3app.js'),
};

export default {
  input: isLibraryMode
    ? path.resolve(__dirname, './app/javascript/entrypoints/sdk.js')
    : entrypoints,
  output: isLibraryMode
    ? {
        dir: 'public/packs',
        entryFileNames: chunkInfo => {
          if (chunkInfo.name === 'sdk') {
            return 'js/sdk.js';
          }
          return 'js/[name].js';
        },
        format: 'iife',
        name: 'sdk',
        inlineDynamicImports: true,
        sourcemap: true,
      }
    : {
        dir: 'public/packs',
        format: 'esm',
        entryFileNames: 'js/[name].js',
        chunkFileNames: 'js/[name]-[hash].js',
        assetFileNames: 'js/assets/[name]-[hash][extname]',
        sourcemap: true,
      },
  plugins,
};
