// Generated by Haxe 3.3.0 (git build development @ b0a6270)
if (process.version < "v4.0.0") console.warn("Module " + (typeof(module) == "undefined" ? "" : module.filename) + " requires node.js version 4.0.0 or higher");
(function () { "use strict";
var $estr = function() { return js_Boot.__string_rec(this,''); };
function $extend(from, fields) {
	function Inherit() {} Inherit.prototype = from; var proto = new Inherit();
	for (var name in fields) proto[name] = fields[name];
	if( fields.toString !== Object.prototype.toString ) proto.toString = fields.toString;
	return proto;
}
var HxOverrides = function() { };
HxOverrides.__name__ = true;
HxOverrides.cca = function(s,index) {
	var x = s.charCodeAt(index);
	if(x != x) {
		return undefined;
	}
	return x;
};
HxOverrides.substr = function(s,pos,len) {
	if(len == null) {
		len = s.length;
	} else if(len < 0) {
		if(pos == 0) {
			len = s.length + len;
		} else {
			return "";
		}
	}
	return s.substr(pos,len);
};
var JsonRpc = function() { };
JsonRpc.__name__ = true;
JsonRpc.error = function(code,message,data) {
	var error = { code : code, message : message};
	if(data != null) {
		error.data = data;
	}
	return error;
};
JsonRpc.request = function(id,method,params) {
	var message = { jsonrpc : "2.0", id : id, method : method};
	if(params == null) {
		message.params = params;
	}
	return message;
};
JsonRpc.notification = function(method,params) {
	var message = { jsonrpc : "2.0", method : method};
	if(params == null) {
		message.params = params;
	}
	return message;
};
JsonRpc.response = function(id,outcome) {
	var response = { jsonrpc : "2.0", id : id};
	switch(outcome[1]) {
	case 0:
		response.error = outcome[2];
		break;
	case 1:
		response.result = outcome[2];
		break;
	}
	return response;
};
var js_node_buffer_Buffer = require("buffer").Buffer;
var MessageBuffer = function(encoding) {
	if(encoding == null) {
		encoding = "utf-8";
	}
	this.encoding = encoding;
	this.index = 0;
	this.buffer = new js_node_buffer_Buffer(8192);
};
MessageBuffer.__name__ = true;
MessageBuffer.prototype = {
	append: function(chunk) {
		var toAppend;
		if(typeof(chunk) == "string") {
			var str = chunk;
			toAppend = new js_node_buffer_Buffer(str.length);
			toAppend.write(str,0,str.length,this.encoding);
		} else {
			toAppend = chunk;
		}
		if(this.buffer.length - this.index >= toAppend.length) {
			toAppend.copy(this.buffer,this.index,0,toAppend.length);
		} else {
			var newSize = (Math.ceil((this.index + toAppend.length) / 8192) + 1) * 8192;
			if(this.index == 0) {
				this.buffer = new js_node_buffer_Buffer(newSize);
				toAppend.copy(this.buffer,0,0,toAppend.length);
			} else {
				this.buffer = js_node_buffer_Buffer.concat([this.buffer.slice(0,this.index),toAppend],newSize);
			}
		}
		this.index += toAppend.length;
	}
	,tryReadHeaders: function() {
		var current = 0;
		while(current + 3 < this.index && (this.buffer[current] != MessageBuffer.CR || this.buffer[current + 1] != MessageBuffer.LF || this.buffer[current + 2] != MessageBuffer.CR || this.buffer[current + 3] != MessageBuffer.LF)) ++current;
		if(current + 3 >= this.index) {
			return null;
		}
		var result = new haxe_ds_StringMap();
		var headers = this.buffer.toString("ascii",0,current).split("\r\n");
		var _g = 0;
		while(_g < headers.length) {
			var header = headers[_g];
			++_g;
			var index = header.indexOf(":");
			if(index == -1) {
				throw new js__$Boot_HaxeError("Message header must separate key and value using :");
			}
			var key = HxOverrides.substr(header,0,index);
			var value = StringTools.trim(HxOverrides.substr(header,index + 1,null));
			if(__map_reserved[key] != null) {
				result.setReserved(key,value);
			} else {
				result.h[key] = value;
			}
		}
		var nextStart = current + 4;
		this.buffer = this.buffer.slice(nextStart);
		this.index = this.index - nextStart;
		return result;
	}
	,tryReadContent: function(length) {
		if(this.index < length) {
			return null;
		}
		var result = this.buffer.toString(this.encoding,0,length);
		this.buffer.copy(this.buffer,0,length);
		this.index -= length;
		return result;
	}
};
var StreamMessageReader = function(readable,encoding) {
	if(encoding == null) {
		encoding = "utf-8";
	}
	this.readable = readable;
	this.buffer = new MessageBuffer(encoding);
};
StreamMessageReader.__name__ = true;
StreamMessageReader.prototype = {
	listen: function(cb) {
		this.nextMessageLength = -1;
		this.callback = cb;
		this.readable.on("data",$bind(this,this.onData));
	}
	,onData: function(data) {
		this.buffer.append(data);
		while(true) {
			if(this.nextMessageLength == -1) {
				var headers = this.buffer.tryReadHeaders();
				if(headers == null) {
					return;
				}
				var contentLength = __map_reserved["Content-Length"] != null?headers.getReserved("Content-Length"):headers.h["Content-Length"];
				if(contentLength == null) {
					throw new js__$Boot_HaxeError("Header must provide a Content-Length property.");
				}
				var length = Std.parseInt(contentLength);
				if(length == null) {
					throw new js__$Boot_HaxeError("Content-Length value must be a number.");
				}
				this.nextMessageLength = length;
			}
			var msg = this.buffer.tryReadContent(this.nextMessageLength);
			if(msg == null) {
				return;
			}
			this.nextMessageLength = -1;
			var json = JSON.parse(msg);
			this.callback(json);
		}
	}
};
var StreamMessageWriter = function(writable,encoding) {
	if(encoding == null) {
		encoding = "utf8";
	}
	this.writable = writable;
	this.encoding = encoding;
};
StreamMessageWriter.__name__ = true;
StreamMessageWriter.prototype = {
	write: function(msg) {
		var json = JSON.stringify(msg);
		var contentLength = js_node_buffer_Buffer.byteLength(json,this.encoding);
		this.writable.write("Content-Length: ","ascii");
		this.writable.write(contentLength == null?"null":"" + contentLength,"ascii");
		this.writable.write("\r\n");
		this.writable.write("\r\n");
		this.writable.write(json,this.encoding);
	}
};
var Main = function() { };
Main.__name__ = true;
Main.main = function() {
	new StreamMessageWriter(js_node_Fs.createWriteStream("input")).write(JsonRpc.request(1,"initialize",{ processId : -1, rootPath : null, capabilities : { }}));
	var reader = new StreamMessageReader(js_node_Fs.createReadStream("input"));
	var writer = new StreamMessageWriter(process.stdout);
	var proto = new Protocol();
	proto.onInitialize = function(params,resolve,reject) {
		resolve({ capabilities : { completionProvider : { resolveProvider : true, triggerCharacters : [".","("]}}});
	};
	proto.onCompletion = function(params1,resolve1,reject1) {
		proto.sendMessage(JsonRpc.notification("window/showMessage",{ type : 3, message : "Hello"}));
		resolve1([{ label : "foo"},{ label : "bar"}]);
	};
	proto.onCompletionItemResolve = function(item,resolve2,reject2) {
		resolve2(item);
	};
	proto.sendMessage = $bind(writer,writer.write);
	reader.listen($bind(proto,proto.handleMessage));
};
Math.__name__ = true;
var Protocol = function() {
};
Protocol.__name__ = true;
Protocol.prototype = {
	handleMessage: function(message) {
		var _gthis = this;
		console.log("Handling message: " + Std.string(message));
		if(Object.prototype.hasOwnProperty.call(message,"id")) {
			var request = message;
			this.handleRequest(request,function(result) {
				_gthis.sendMessage(JsonRpc.response(request.id,haxe_ds_Either.Right(result)));
			},function(code,message1,data) {
				_gthis.sendMessage(JsonRpc.response(request.id,haxe_ds_Either.Left(JsonRpc.error(code,message1,data))));
			});
		} else {
			this.handleNotification(message);
		}
	}
	,sendMessage: function(message) {
	}
	,handleRequest: function(request,resolve,reject) {
		switch(request.method) {
		case "codeLens/resolve":
			this.onCodeLensResolve(request.params,resolve,function(c,m) {
				reject(c,m,null);
			});
			break;
		case "completionItem/resolve":
			this.onCompletionItemResolve(request.params,resolve,function(c1,m1) {
				reject(c1,m1,null);
			});
			break;
		case "initialize":
			this.onInitialize(request.params,resolve,reject);
			break;
		case "textDocument/codeAction":
			this.onCodeAction(request.params,resolve,function(c2,m2) {
				reject(c2,m2,null);
			});
			break;
		case "textDocument/codeLens":
			this.onCodeLens(request.params,resolve,function(c3,m3) {
				reject(c3,m3,null);
			});
			break;
		case "textDocument/completion":
			this.onCompletion(request.params,resolve,function(c4,m4) {
				reject(c4,m4,null);
			});
			break;
		case "textDocument/definition":
			this.onGotoDefinition(request.params,resolve,function(c5,m5) {
				reject(c5,m5,null);
			});
			break;
		case "textDocument/documentHighlight":
			this.onDocumentHighlights(request.params,resolve,function(c6,m6) {
				reject(c6,m6,null);
			});
			break;
		case "textDocument/documentSymbol":
			this.onDocumentSymbols(request.params,resolve,function(c7,m7) {
				reject(c7,m7,null);
			});
			break;
		case "textDocument/formatting":
			this.onDocumentFormatting(request.params,resolve,function(c8,m8) {
				reject(c8,m8,null);
			});
			break;
		case "textDocument/hover":
			this.onHover(request.params,resolve,function(c9,m9) {
				reject(c9,m9,null);
			});
			break;
		case "textDocument/onTypeFormatting":
			this.onDocumentOnTypeFormatting(request.params,resolve,function(c10,m10) {
				reject(c10,m10,null);
			});
			break;
		case "textDocument/references":
			this.onFindReferences(request.params,resolve,function(c11,m11) {
				reject(c11,m11,null);
			});
			break;
		case "textDocument/rename":
			this.onRename(request.params,resolve,function(c12,m12) {
				reject(c12,m12,null);
			});
			break;
		case "textDocument/signatureHelp":
			this.onSignatureHelp(request.params,resolve,function(c13,m13) {
				reject(c13,m13,null);
			});
			break;
		case "workspace/symbol":
			this.onWorkspaceSymbols(request.params,resolve,function(c14,m14) {
				reject(c14,m14,null);
			});
			break;
		default:
			reject(-32601,"Method '" + request.method + "' not found",null);
		}
	}
	,handleNotification: function(notification) {
		switch(notification.method) {
		case "exit":
			this.onExit();
			break;
		case "shutdown":
			this.onShutdown();
			break;
		case "textDocument/didChange":
			this.onDidChangeTextDocument(notification.params);
			break;
		case "textDocument/didClose":
			this.onDidCloseTextDocument(notification.params);
			break;
		case "textDocument/didOpen":
			this.onDidOpenTextDocument(notification.params);
			break;
		case "textDocument/didSave":
			this.onDidSaveTextDocument(notification.params);
			break;
		case "textDocument/publishDiagnostics":
			this.onPublishDiagnostics(notification.params);
			break;
		case "window/logMessage":
			this.onLogMessage(notification.params);
			break;
		case "window/showMessage":
			this.onShowMessage(notification.params);
			break;
		case "workspace/didChangeConfiguration":
			this.onDidChangeConfiguration(notification.params);
			break;
		case "workspace/didChangeWatchedFiles":
			this.onDidChangeWatchedFiles(notification.params);
			break;
		}
	}
	,onInitialize: function(params,resolve,reject) {
	}
	,onShutdown: function() {
	}
	,onExit: function() {
	}
	,onShowMessage: function(params) {
	}
	,onLogMessage: function(params) {
	}
	,onDidChangeConfiguration: function(params) {
	}
	,onDidOpenTextDocument: function(params) {
	}
	,onDidChangeTextDocument: function(params) {
	}
	,onDidCloseTextDocument: function(params) {
	}
	,onDidSaveTextDocument: function(params) {
	}
	,onDidChangeWatchedFiles: function(params) {
	}
	,onPublishDiagnostics: function(params) {
	}
	,onCompletion: function(params,resolve,reject) {
	}
	,onCompletionItemResolve: function(params,resolve,reject) {
	}
	,onHover: function(params,resolve,reject) {
	}
	,onSignatureHelp: function(params,resolve,reject) {
	}
	,onGotoDefinition: function(params,resolve,reject) {
	}
	,onFindReferences: function(params,resolve,reject) {
	}
	,onDocumentHighlights: function(params,resolve,reject) {
	}
	,onDocumentSymbols: function(params,resolve,reject) {
	}
	,onWorkspaceSymbols: function(params,resolve,reject) {
	}
	,onCodeAction: function(params,resolve,reject) {
	}
	,onCodeLens: function(params,resolve,reject) {
	}
	,onCodeLensResolve: function(params,resolve,reject) {
	}
	,onDocumentFormatting: function(params,resolve,reject) {
	}
	,onDocumentOnTypeFormatting: function(params,resolve,reject) {
	}
	,onRename: function(params,resolve,reject) {
	}
};
var Std = function() { };
Std.__name__ = true;
Std.string = function(s) {
	return js_Boot.__string_rec(s,"");
};
Std.parseInt = function(x) {
	var v = parseInt(x,10);
	if(v == 0 && (HxOverrides.cca(x,1) == 120 || HxOverrides.cca(x,1) == 88)) {
		v = parseInt(x);
	}
	if(isNaN(v)) {
		return null;
	}
	return v;
};
var StringTools = function() { };
StringTools.__name__ = true;
StringTools.isSpace = function(s,pos) {
	var c = HxOverrides.cca(s,pos);
	if(!(c > 8 && c < 14)) {
		return c == 32;
	} else {
		return true;
	}
};
StringTools.ltrim = function(s) {
	var l = s.length;
	var r = 0;
	while(r < l && StringTools.isSpace(s,r)) ++r;
	if(r > 0) {
		return HxOverrides.substr(s,r,l - r);
	} else {
		return s;
	}
};
StringTools.rtrim = function(s) {
	var l = s.length;
	var r = 0;
	while(r < l && StringTools.isSpace(s,l - r - 1)) ++r;
	if(r > 0) {
		return HxOverrides.substr(s,0,l - r);
	} else {
		return s;
	}
};
StringTools.trim = function(s) {
	return StringTools.ltrim(StringTools.rtrim(s));
};
var haxe_IMap = function() { };
haxe_IMap.__name__ = true;
var haxe_ds_Either = { __ename__ : true, __constructs__ : ["Left","Right"] };
haxe_ds_Either.Left = function(v) { var $x = ["Left",0,v]; $x.__enum__ = haxe_ds_Either; $x.toString = $estr; return $x; };
haxe_ds_Either.Right = function(v) { var $x = ["Right",1,v]; $x.__enum__ = haxe_ds_Either; $x.toString = $estr; return $x; };
var haxe_ds_StringMap = function() {
	this.h = { };
};
haxe_ds_StringMap.__name__ = true;
haxe_ds_StringMap.__interfaces__ = [haxe_IMap];
haxe_ds_StringMap.prototype = {
	setReserved: function(key,value) {
		if(this.rh == null) {
			this.rh = { };
		}
		this.rh["$" + key] = value;
	}
	,getReserved: function(key) {
		if(this.rh == null) {
			return null;
		} else {
			return this.rh["$" + key];
		}
	}
};
var haxe_io_Bytes = function() { };
haxe_io_Bytes.__name__ = true;
var js__$Boot_HaxeError = function(val) {
	Error.call(this);
	this.val = val;
	this.message = String(val);
	if(Error.captureStackTrace) {
		Error.captureStackTrace(this,js__$Boot_HaxeError);
	}
};
js__$Boot_HaxeError.__name__ = true;
js__$Boot_HaxeError.wrap = function(val) {
	if((val instanceof Error)) {
		return val;
	} else {
		return new js__$Boot_HaxeError(val);
	}
};
js__$Boot_HaxeError.__super__ = Error;
js__$Boot_HaxeError.prototype = $extend(Error.prototype,{
});
var js_Boot = function() { };
js_Boot.__name__ = true;
js_Boot.__string_rec = function(o,s) {
	if(o == null) {
		return "null";
	}
	if(s.length >= 5) {
		return "<...>";
	}
	var t = typeof(o);
	if(t == "function" && (o.__name__ || o.__ename__)) {
		t = "object";
	}
	switch(t) {
	case "function":
		return "<function>";
	case "object":
		if(o instanceof Array) {
			if(o.__enum__) {
				if(o.length == 2) {
					return o[0];
				}
				var str = o[0] + "(";
				s += "\t";
				var _g1 = 2;
				var _g = o.length;
				while(_g1 < _g) {
					var i = _g1++;
					if(i != 2) {
						str += "," + js_Boot.__string_rec(o[i],s);
					} else {
						str += js_Boot.__string_rec(o[i],s);
					}
				}
				return str + ")";
			}
			var l = o.length;
			var i1;
			var str1 = "[";
			s += "\t";
			var _g11 = 0;
			var _g2 = l;
			while(_g11 < _g2) {
				var i2 = _g11++;
				str1 += (i2 > 0?",":"") + js_Boot.__string_rec(o[i2],s);
			}
			str1 += "]";
			return str1;
		}
		var tostr;
		try {
			tostr = o.toString;
		} catch( e ) {
			return "???";
		}
		if(tostr != null && tostr != Object.toString && typeof(tostr) == "function") {
			var s2 = o.toString();
			if(s2 != "[object Object]") {
				return s2;
			}
		}
		var k = null;
		var str2 = "{\n";
		s += "\t";
		var hasp = o.hasOwnProperty != null;
		for( var k in o ) {
		if(hasp && !o.hasOwnProperty(k)) {
			continue;
		}
		if(k == "prototype" || k == "__class__" || k == "__super__" || k == "__interfaces__" || k == "__properties__") {
			continue;
		}
		if(str2.length != 2) {
			str2 += ", \n";
		}
		str2 += s + k + " : " + js_Boot.__string_rec(o[k],s);
		}
		s = s.substring(1);
		str2 += "\n" + s + "}";
		return str2;
	case "string":
		return o;
	default:
		return String(o);
	}
};
var js_node_Fs = require("fs");
var $_, $fid = 0;
function $bind(o,m) { if( m == null ) return null; if( m.__id__ == null ) m.__id__ = $fid++; var f; if( o.hx__closures__ == null ) o.hx__closures__ = {}; else f = o.hx__closures__[m.__id__]; if( f == null ) { f = function(){ return f.method.apply(f.scope, arguments); }; f.scope = o; f.method = m; o.hx__closures__[m.__id__] = f; } return f; }
String.__name__ = true;
Array.__name__ = true;
var __map_reserved = {}
MessageBuffer.CR = new js_node_buffer_Buffer("\r","ascii")[0];
MessageBuffer.LF = new js_node_buffer_Buffer("\n","ascii")[0];
Main.main();
})();