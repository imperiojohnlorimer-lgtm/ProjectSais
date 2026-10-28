// Shows a PDF or a Word file inside the app. Only a browser can: on any other
// build [WebDocumentView.isSupported] is false and the preview offers
// Download instead.
export 'web_document_view_stub.dart'
    if (dart.library.js_interop) 'web_document_view_web.dart';
