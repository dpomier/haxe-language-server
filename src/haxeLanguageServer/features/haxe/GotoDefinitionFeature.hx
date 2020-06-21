package haxeLanguageServer.features.haxe;

import haxe.display.Display;
import haxeLanguageServer.helper.HaxePosition;
import jsonrpc.CancellationToken;
import jsonrpc.ResponseError;
import jsonrpc.Types.NoData;

class GotoDefinitionFeature {
	final context:Context;

	public function new(context) {
		this.context = context;
		context.languageServerProtocol.onRequest(DefinitionRequest.type, onGotoDefinition);
	}

	public function onGotoDefinition(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void,
			reject:ResponseError<NoData>->Void) {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null || !uri.isFile()) {
			return reject.noFittingDocument(uri);
		}
		final handle = if (context.haxeServer.supports(DisplayMethods.GotoDefinition)) handleJsonRpc else handleLegacy;
		handle(params, token, resolve, reject, doc, doc.offsetAt(params.position));
	}

	function handleJsonRpc(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument, offset:Int) {
		context.callHaxeMethod(DisplayMethods.GotoDefinition, {file: doc.uri.toFsPath(), contents: doc.content, offset: offset}, token, function(locations) {
			resolve(locations.map(location -> {
				{
					uri: location.file.toUri(),
					range: location.range
				}
			}));
			return null;
		}, reject.handler());
	}

	function handleLegacy(params:TextDocumentPositionParams, token:CancellationToken, resolve:Definition->Void, reject:ResponseError<NoData>->Void,
			doc:TextDocument, offset:Int) {
		final bytePos = context.displayOffsetConverter.characterOffsetToByteOffset(doc.content, offset);
		final args = ['${doc.uri.toFsPath()}@$bytePos@position'];
		context.callDisplay("@position", args, doc.content, token, function(r) {
			switch r {
				case DCancelled:
					resolve(null);
				case DResult(data):
					final xml = try Xml.parse(data).firstElement() catch (_:Any) null;
					if (xml == null)
						return reject.invalidXml(data);

					final positions = [for (el in xml.elements()) el.firstChild().nodeValue];
					if (positions.length == 0)
						resolve([]);
					final results = [];
					for (pos in positions) {
						final location = HaxePosition.parse(pos, doc, null,
							context.displayOffsetConverter); // no cache because this right now only returns one position
						if (location == null) {
							trace("Got invalid position: " + pos);
							continue;
						}
						results.push(location);
					}
					resolve(results);
			}
		}, reject.handler());
	}
}
