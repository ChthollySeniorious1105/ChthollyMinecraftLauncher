{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    // CJK / emoji fallback fonts are fetched on demand; fonts.gstatic.com is
    // unreachable on many networks in mainland China, the .cn mirror works everywhere.
    fontFallbackBaseUrl: 'https://fonts.gstatic.cn/s/',
  },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    const loading = document.getElementById('aurora-loading');
    if (loading) loading.remove();
  },
});
