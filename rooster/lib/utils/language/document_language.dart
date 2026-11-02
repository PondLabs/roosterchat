import 'document_language_native.dart'
    if (dart.library.js_interop) 'document_language_web.dart' as impl;

/// Sets the web page's `lang` to [tag] (BCP 47), which screen readers read
/// it by. Native has no page, so it does nothing.
void setDocumentLanguage(String tag) => impl.setDocumentLanguage(tag);
