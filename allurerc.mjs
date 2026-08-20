// Keep local scoreboard reports directly openable from Finder. The default
// multi-file report fetches JSON at runtime, which browsers block from file://.
export default {
  plugins: {
    awesome: {
      options: {
        singleFile: true,
        reportLanguage: 'en',
      },
    },
  },
};
