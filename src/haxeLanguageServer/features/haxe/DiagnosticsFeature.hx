package haxeLanguageServer.features.haxe;

import haxe.ds.BalancedTree;
import haxe.io.Path;
import haxeLanguageServer.Configuration;
import haxeLanguageServer.LanguageServerMethods;
import haxeLanguageServer.features.haxe.codeAction.CodeActionFeature;
import haxeLanguageServer.features.haxe.codeAction.OrganizeImportsFeature;
import haxeLanguageServer.helper.DocHelper;
import haxeLanguageServer.helper.ImportHelper;
import haxeLanguageServer.helper.PathHelper;
import haxeLanguageServer.helper.TypeHelper;
import haxeLanguageServer.helper.WorkspaceEditHelper;
import haxeLanguageServer.server.DisplayResult;
import js.node.ChildProcess;

using Lambda;

class DiagnosticsFeature {
	static inline final DiagnosticsSource = "diagnostics";
	static inline final SortImportsUsingsTitle = "Sort imports/usings";
	static inline final OrganizeImportsUsingsTitle = "Organize imports/usings";
	static inline final RemoveUnusedImportUsingTitle = "Remove unused import/using";
	static inline final RemoveAllUnusedImportsUsingsTitle = "Remove all unused imports/usings";

	final context:Context;
	final diagnosticsArguments:Map<DocumentUri, DiagnosticsMap<Any>>;
	final errorUri:DocumentUri;

	var haxelibPath:Null<FsPath>;

	public function new(context:Context) {
		this.context = context;
		diagnosticsArguments = new Map();
		errorUri = new FsPath(Path.join([context.workspacePath.toString(), "Error"])).toUri();

		ChildProcess.exec(context.config.haxelib.executable + " config", (error, stdout, stderr) -> haxelibPath = new FsPath(stdout.trim()));

		context.registerCodeActionContributor(getCodeActions);
		context.languageServerProtocol.onNotification(LanguageServerMethods.RunGlobalDiagnostics, onRunGlobalDiagnostics);
	}

	function onRunGlobalDiagnostics(_) {
		final stopProgress = context.startProgress("Collecting Diagnostics");
		final onResolve = context.startTimer("@diagnostics");

		context.callDisplay("global diagnostics", ["diagnostics"], null, null, function(result) {
			processDiagnosticsReply(null, onResolve, result);
			context.languageServerProtocol.sendNotification(LanguageServerMethods.DidRunRunGlobalDiagnostics);
			stopProgress();
		}, function(error) {
			processErrorReply(null, error);
			stopProgress();
		});
	}

	function processErrorReply(uri:Null<DocumentUri>, error:String) {
		if (!extractDiagnosticsFromHaxeError(uri, error) && !extractDiagnosticsFromHaxeError2(error)) {
			if (uri != null) {
				clearDiagnostics(uri);
			}
			clearDiagnostics(errorUri);
		}
		trace(error);
	}

	function extractDiagnosticsFromHaxeError(uri:Null<DocumentUri>, error:String):Bool {
		final problemMatcher = ~/(.+):(\d+): (?:lines \d+-(\d+)|character(?:s (\d+)-| )(\d+)) : (?:(Warning) : )?(.*)/;
		if (!problemMatcher.match(error))
			return false;

		var file = problemMatcher.matched(1);
		if (!Path.isAbsolute(file))
			file = Path.join([Sys.getCwd(), file]);

		final targetUri = new FsPath(file).toUri();
		if (targetUri != uri)
			return false; // only allow error reply diagnostics in current file for now (clearing becomes annoying otherwise...)

		if (isPathFiltered(targetUri.toFsPath()))
			return false;

		inline function getInt(i)
			return Std.parseInt(problemMatcher.matched(i));

		final line = getInt(2);
		var endLine = getInt(3);
		final column = getInt(4);
		final endColumn = getInt(5);

		function makePosition(line:Int, character:Null<Int>) {
			return {
				line: line - 1,
				character: if (character == null) 0 else context.displayOffsetConverter.positionCharToZeroBasedColumn(character)
			}
		}

		if (endLine == null)
			endLine = line;
		final position = makePosition(line, column);
		final endPosition = makePosition(endLine, endColumn);

		final diag = {
			range: {start: position, end: endPosition},
			source: DiagnosticsSource,
			severity: DiagnosticSeverity.Error,
			message: problemMatcher.matched(7)
		};
		publishDiagnostic(uri, diag, error);
		return true;
	}

	function extractDiagnosticsFromHaxeError2(error:String):Bool {
		final problemMatcher = ~/^(Error): (.*)$/;
		if (!problemMatcher.match(error)) {
			return false;
		}

		final diag = {
			range: {start: {line: 0, character: 0}, end: {line: 0, character: 0}},
			source: DiagnosticsSource,
			severity: DiagnosticSeverity.Error,
			message: problemMatcher.matched(2)
		};
		publishDiagnostic(errorUri, diag, error);
		return true;
	}

	function publishDiagnostic(uri:DocumentUri, diag:Diagnostic, error:String) {
		context.languageServerProtocol.sendNotification(PublishDiagnosticsNotification.type, {uri: uri, diagnostics: [diag]});
		final argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();
		argumentsMap.set({code: CompilerError, range: diag.range}, error);
	}

	function processDiagnosticsReply(uri:Null<DocumentUri>, onResolve:(result:Dynamic, ?debugInfo:String) -> Void, result:DisplayResult) {
		clearDiagnostics(errorUri);
		switch result {
			case DResult(s):
				final data:Array<HaxeDiagnosticResponse<Any>> = try {
					haxe.Json.parse(s);
				} catch (e) {
					trace("Error parsing diagnostics response: " + Std.string(e));
					return;
				}

				var count = 0;
				final sent = new Map<DocumentUri, Bool>();
				for (data in data) {
					count += data.diagnostics.length;

					var file = data.file;
					if (data.file == null) {
						// LSP always needs a URI for now (https://github.com/Microsoft/language-server-protocol/issues/256)
						file = errorUri.toFsPath();
					}
					if (isPathFiltered(file))
						continue;

					final uri = file.toUri();
					final argumentsMap = diagnosticsArguments[uri] = new DiagnosticsMap();

					final newDiagnostics = filterRelevantDiagnostics(data.diagnostics);
					final diagnostics = new Array<Diagnostic>();
					for (hxDiag in newDiagnostics) {
						var range = hxDiag.range;
						if (hxDiag.range == null) {
							// range is not optional in the LSP yet
							range = {
								start: {line: 0, character: 0},
								end: {line: 0, character: 0}
							}
						}

						final kind:Int = hxDiag.kind;
						final diag:Diagnostic = {
							range: range,
							source: DiagnosticsSource,
							code: kind,
							severity: hxDiag.severity,
							message: hxDiag.kind.getMessage(hxDiag.args)
						}
						if (kind == RemovableCode
							|| kind == UnusedImport
							|| diag.message.contains("has no effect")
							|| kind == InactiveBlock) {
							diag.severity = Hint;
							diag.tags = [Unnecessary];
						}
						if (diag.message == "This case is unused") {
							diag.tags = [Unnecessary];
						}
						if (kind == DeprecationWarning) {
							diag.tags = [Deprecated];
						}
						argumentsMap.set({code: kind, range: diag.range}, hxDiag.args);
						diagnostics.push(diag);
					}
					context.languageServerProtocol.sendNotification(PublishDiagnosticsNotification.type, {uri: uri, diagnostics: diagnostics});
					sent[uri] = true;
				}

				inline function removeOldDiagnostics(uri:DocumentUri) {
					if (!sent.exists(uri))
						clearDiagnostics(uri);
				}

				if (uri == null) {
					for (uri in diagnosticsArguments.keys())
						removeOldDiagnostics(uri);
				} else {
					removeOldDiagnostics(uri);
				}

				onResolve(data, count + " diagnostics");

			case DCancelled:
		}
	}

	function isPathFiltered(path:FsPath):Bool {
		final pathFilter = PathHelper.preparePathFilter(context.config.user.diagnosticsPathFilter, haxelibPath, context.workspacePath);
		return !PathHelper.matches(path, pathFilter);
	}

	function filterRelevantDiagnostics(diagnostics:Array<HaxeDiagnostic<Any>>):Array<HaxeDiagnostic<Any>> {
		// hide regular compiler errors while there's parser errors, they can be misleading
		final hasProblematicParserErrors = diagnostics.find(d -> switch (d.kind : Int) {
			case ParserError: d.args != "Missing ;"; // don't be too strict
			case _: false;
		}) != null;
		if (hasProblematicParserErrors) {
			diagnostics = diagnostics.filter(d -> switch (d.kind : Int) {
				case CompilerError, UnresolvedIdentifier: false;
				case _: true;
			});
		}

		// hide unused import warnings while there's compiler errors (to avoid false positives)
		final hasCompilerErrors = diagnostics.find(d -> d.kind == cast CompilerError) != null;
		if (hasCompilerErrors) {
			diagnostics = diagnostics.filter(d -> d.kind != cast UnusedImport);
		}

		// hide inactive blocks that are contained within other inactive blocks
		diagnostics = diagnostics.filter(a -> !diagnostics.exists(b -> a != b && b.range.contains(a.range)));

		return diagnostics;
	}

	public function clearDiagnostics(uri:DocumentUri) {
		if (diagnosticsArguments.remove(uri))
			context.languageServerProtocol.sendNotification(PublishDiagnosticsNotification.type, {uri: uri, diagnostics: []});
	}

	public function publishDiagnostics(uri:DocumentUri) {
		if (!uri.isFile() || isPathFiltered(uri.toFsPath())) {
			clearDiagnostics(uri);
			return;
		}
		final doc:Null<HaxeDocument> = context.documents.getHaxe(uri);
		if (doc != null) {
			final onResolve = context.startTimer("@diagnostics");
			context.callDisplay("@diagnostics", [doc.uri.toFsPath() + "@0@diagnostics"], null, null, processDiagnosticsReply.bind(uri, onResolve),
				processErrorReply.bind(uri));
		}
	}

	function getCodeActions<T>(params:CodeActionParams) {
		if (!params.textDocument.uri.isFile()) {
			return [];
		}
		var actions:Array<CodeAction> = [];
		for (d in params.context.diagnostics) {
			if (!(d.code is Int)) // our codes are int, so we don't handle other stuff
				continue;
			final code = new DiagnosticKind<T>(d.code);
			actions = actions.concat(switch code {
				case UnusedImport: getUnusedImportActions(params, d);
				case UnresolvedIdentifier: getUnresolvedIdentifierActions(params, d);
				case CompilerError: getCompilerErrorActions(params, d);
				case RemovableCode: getRemovableCodeActions(params, d);
				case _: [];
			});
		}
		actions = getOrganizeImportActions(params, actions).concat(actions);
		actions = actions.filterDuplicates((a1, a2) -> a1.title == a2.title);
		return actions;
	}

	function getUnusedImportActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
		final doc = context.documents.getHaxe(params.textDocument.uri);
		if (doc == null) {
			return [];
		}
		return [
			{
				title: RemoveUnusedImportUsingTitle,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [
					{
						range: DocHelper.untrimRange(doc, d.range),
						newText: ""
					}
				]),
				diagnostics: [d],
				isPreferred: true
			}
		];
	}

	function getUnresolvedIdentifierActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
		var actions:Array<CodeAction> = [];
		final args = getDiagnosticsArguments(params.textDocument.uri, UnresolvedIdentifier, d.range);
		final importCount = args.count(a -> a.kind == Import);
		for (arg in args) {
			actions = actions.concat(switch arg.kind {
				case Import: getUnresolvedImportActions(params, d, arg, importCount);
				case Typo: getTypoActions(params, d, arg);
			});
		}
		return actions;
	}

	function getUnresolvedImportActions(params:CodeActionParams, d:Diagnostic, arg, importCount:Int):Array<CodeAction> {
		final doc = context.documents.getHaxe(params.textDocument.uri);
		if (doc == null) {
			return [];
		}
		final preferredStyle = context.config.user.codeGeneration.imports.style;
		final secondaryStyle:ImportStyle = if (preferredStyle == Type) Module else Type;

		final importPosition = determineImportPosition(doc);
		function makeImportAction(style:ImportStyle):CodeAction {
			final path = if (style == Module) TypeHelper.getModule(arg.name) else arg.name;
			return {
				title: "Import " + path,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [createImportsEdit(doc, importPosition, [arg.name], style)]),
				diagnostics: [d]
			};
		}

		final preferred = makeImportAction(preferredStyle);
		final secondary = makeImportAction(secondaryStyle);
		if (importCount == 1) {
			preferred.isPreferred = true;
		}
		final actions = [preferred, secondary];

		actions.push({
			title: "Change to " + arg.name,
			kind: QuickFix,
			edit: WorkspaceEditHelper.create(context, params, [{range: d.range, newText: arg.name}]),
			diagnostics: [d]
		});

		return actions;
	}

	function getTypoActions(params:CodeActionParams, d:Diagnostic, arg):Array<CodeAction> {
		return [
			{
				title: "Change to " + arg.name,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: d.range, newText: arg.name}]),
				diagnostics: [d]
			}
		];
	}

	function getCompilerErrorActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
		final actions:Array<CodeAction> = [];
		final arg = getDiagnosticsArguments(params.textDocument.uri, CompilerError, d.range);
		final suggestionsRe = ~/\(Suggestions?: (.*)\)/;
		if (suggestionsRe.match(arg)) {
			final suggestions = suggestionsRe.matched(1).split(",");
			// Haxe reports the entire expression, not just the field position, so we have to be a bit creative here.
			final range = d.range;
			final fieldRe = ~/has no field ([^ ]+) /;
			if (fieldRe.match(arg)) {
				range.start.character = range.end.character - fieldRe.matched(1).length;
			}
			for (suggestion in suggestions) {
				suggestion = suggestion.trim();
				actions.push({
					title: "Change to " + suggestion,
					kind: QuickFix,
					edit: WorkspaceEditHelper.create(context, params, [{range: range, newText: suggestion}]),
					diagnostics: [d]
				});
			}
			return actions;
		}

		final invalidPackageRe = ~/Invalid package : ([\w.]*) should be ([\w.]*)/;
		if (invalidPackageRe.match(arg)) {
			final is = invalidPackageRe.matched(1);
			final shouldBe = invalidPackageRe.matched(2);
			final text = context.documents.getHaxe(params.textDocument.uri) !.getText(d.range);
			final replacement = text.replace(is, shouldBe);
			actions.push({
				title: "Change to " + replacement,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: d.range, newText: replacement}]),
				diagnostics: [d],
				isPreferred: true
			});
		}

		if (context.haxeServer.haxeVersion.major >= 4 // unsuitable error range before Haxe 4
			&& arg.contains("should be declared with 'override' since it is inherited from superclass")) {
			actions.push({
				title: "Add override keyword",
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: d.range.start.toRange(), newText: "override "}]),
				diagnostics: [d],
				isPreferred: true
			});
		}

		return actions;
	}

	function getRemovableCodeActions(params:CodeActionParams, d:Diagnostic):Array<CodeAction> {
		final range = getDiagnosticsArguments(params.textDocument.uri, RemovableCode, d.range).range;
		if (range == null) {
			return [];
		}
		return [
			{
				title: "Remove",
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, [{range: range, newText: ""}]),
				diagnostics: [d],
				isPreferred: true
			}
		];
	}

	function getOrganizeImportActions(params:CodeActionParams, existingActions:Array<CodeAction>):Array<CodeAction> {
		final uri = params.textDocument.uri;
		final doc = context.documents.getHaxe(uri);
		if (doc == null) {
			return [];
		}
		final map = diagnosticsArguments[uri];
		final removeUnusedFixes = if (map == null) [] else [
			for (key in map.keys()) {
				if (key.code == UnusedImport) {
					WorkspaceEditHelper.removeText(DocHelper.untrimRange(doc, key.range));
				}
			}
		];

		final sortFixes = OrganizeImportsFeature.organizeImports(doc, context, []);

		final unusedRanges:Array<Range> = removeUnusedFixes.map(edit -> edit.range);
		final organizeFixes = removeUnusedFixes.concat(OrganizeImportsFeature.organizeImports(doc, context, unusedRanges));

		final diagnostics = existingActions.filter(action -> action.title == RemoveUnusedImportUsingTitle)
			.map(action -> action.diagnostics)
			.flatten()
			.array();
		final actions:Array<CodeAction> = [
			{
				title: SortImportsUsingsTitle,
				kind: CodeActionFeature.SourceSortImports,
				edit: WorkspaceEditHelper.create(context, params, sortFixes)
			},
			{
				title: OrganizeImportsUsingsTitle,
				kind: SourceOrganizeImports,
				edit: WorkspaceEditHelper.create(context, params, organizeFixes),
				diagnostics: diagnostics
			}
		];

		if (diagnostics.length > 0 && removeUnusedFixes.length > 1) {
			actions.push({
				title: RemoveAllUnusedImportsUsingsTitle,
				kind: QuickFix,
				edit: WorkspaceEditHelper.create(context, params, removeUnusedFixes),
				diagnostics: diagnostics
			});
		}

		return actions;
	}

	inline function getDiagnosticsArguments<T>(uri:DocumentUri, kind:DiagnosticKind<T>, range:Range):T {
		final map = diagnosticsArguments[uri];
		return if (map == null) null else map.get({code: kind, range: range});
	}
}

private enum abstract UnresolvedIdentifierSuggestion(Int) {
	final Import;
	final Typo;
}

private enum abstract DiagnosticKind<T>(Int) from Int to Int {
	final UnusedImport:DiagnosticKind<Void>;
	final UnresolvedIdentifier:DiagnosticKind<Array<{kind:UnresolvedIdentifierSuggestion, name:String}>>;
	final CompilerError:DiagnosticKind<String>;
	final RemovableCode:DiagnosticKind<{description:String, range:Range}>;
	final ParserError:DiagnosticKind<String>;
	final DeprecationWarning:DiagnosticKind<String>;
	final InactiveBlock:DiagnosticKind<Void>;
	public inline function new(i:Int) {
		this = i;
	}

	public function getMessage(args:T) {
		return switch (this : DiagnosticKind<T>) {
			case UnusedImport: "Unused import/using";
			case UnresolvedIdentifier: "Unresolved identifier";
			case CompilerError: args.trim();
			case RemovableCode: args.description;
			case ParserError: args;
			case DeprecationWarning: args;
			case InactiveBlock: "Inactive conditional compilation block";
		}
	}
}

private typedef HaxeDiagnostic<T> = {
	final kind:DiagnosticKind<T>;
	final ?range:Range;
	final severity:DiagnosticSeverity;
	final args:T;
}

private typedef HaxeDiagnosticResponse<T> = {
	final ?file:FsPath;
	final diagnostics:Array<HaxeDiagnostic<T>>;
}

private typedef DiagnosticsMapKey = {code:Int, range:Range};

private class DiagnosticsMap<T> extends BalancedTree<DiagnosticsMapKey, T> {
	override function compare(k1:DiagnosticsMapKey, k2:DiagnosticsMapKey) {
		final start1 = k1.range.start;
		final start2 = k2.range.start;
		final end1 = k1.range.end;
		final end2 = k2.range.end;
		inline function compare(i1, i2, e) {
			return i1 < i2 ? -1 : i1 > i2 ? 1 : e;
		}
		return compare(k1.code, k2.code,
			compare(start1.line, start2.line,
				compare(start1.character, start2.character, compare(end1.line, end2.line, compare(end1.character, end2.character, 0)))));
	}
}
