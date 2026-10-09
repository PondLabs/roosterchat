import 'package:web/web.dart' as web;

void setDocumentLanguage(String tag) =>
    web.document.documentElement?.setAttribute('lang', tag);
