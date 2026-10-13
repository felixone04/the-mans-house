{{flutter_js}}
{{flutter_build_config}}

// Avvio senza service worker: la memoria offline di Flutter faceva vedere
// sui telefoni la versione vecchia dell'app anche dopo un aggiornamento.
_flutter.loader.load();
