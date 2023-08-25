## # Python Bindings 🐍
## 
##   Provides bindings for Python programming language
## 
import
  # Stdlib
  sugar,
  tables,
  strtabs,
  strformat,
  # NimPy lib
  nimpy,
  nimpy/[py_types],
  # nimja
  nimja,
  # HappyX
  ../ssr/[server, cors],
  ../core/[constants, exceptions],
  ../routing/[routing],
  ./python_types


pyExportModule(name = "happyx", doc = """
HappyX web framework
""")


proc newServerPy*(address: string = "127.0.0.1", port: int = 5000): Server {.exportpy: "new_server".} =
  ## Creates a new Server object.
  ## 
  ## Arguments:
  ## - address: string = "127.0.0.1"
  ## - port: int = 5000
  newServer(address, port)


proc happyxVersion*: string {.exportpy: "happyx_version".} =
  ## Returns current HappyX version
  HpxVersion


proc registerCORS*(allow_origins: string, allow_methods: string,
                   allow_headers: string, credentials: bool) {.exportpy: "reg_CORS".} =
  ## Registers Cross-Origins Resource Sharing at Runtime
  setCors(allow_origins, allow_methods, allow_headers, credentials)


proc close*(self: python_types.WebSocket) {.exportpy.} =
  self.ws.close()


proc receiveText*(self: python_types.WebSocket): string {.exportpy: "receive_text".} =
  ## Receives raw text data from WebSocket
  self.data


proc receiveJson*(self: python_types.WebSocket): JsonNode {.exportpy: "receive_json".} =
  ## Receives JSON data from WebSocket
  parseJson(self.data)


proc sendText*(self: python_types.WebSocket, value: string) {.exportpy: "send_text".} =
  ## Sends raw text to WebSocket connection
  waitFor self.ws.send(value)


proc sendJson*(self: python_types.WebSocket, value: JsonNode) {.exportpy: "send_json".} =
  ## Sends JSON to WebSocket connection
  waitFor self.ws.send($value)


proc id*(self: python_types.WebSocket): uint64 {.exportpy.} =
  ## Returns current WebSocket unique ID.
  self.id


proc state*(self: python_types.WebSocket): string {.exportpy.} =
  ## Returns current WebSocket state.
  ## 
  ## "connect" - WebSocket connection was created. Can send data. Can't receive data.
  ## "open" - WebSocket connection is opened. Can send/receive data.
  ## "close" - WebSocket connectin os closed. Can't send/receive data.
  ## "mismatch_protocol" - WebSocket Mismatch Protocol Error. Can't send/receive data.
  ## "handshake_error" - WebSocket Handshake Error (no Sec-WebSocket-Version in headers). Can't send/receive data.
  ## "error" - any other WebSocket error. Can't send/receive data.
  case self.state
  of wssConnect: "connect"
  of wssOpen: "open"
  of wssClose: "close"
  of wssHandshakeError: "handshake_error"
  of wssMismatchProtocol: "mismatch_protocol"
  of wssError: "error"


proc `==`*(self, other: python_types.WebSocket): bool {.exportpy: "__eq__".} =
  self.id == other.id


proc newResponse*(data: string, status_code: int = 200, headers: PyObject = pyDict()): ResponseObj {.exportpy: "Response".} =
  ## Raw response object
  ResponseObj(data: data, statusCode: status_code, headers: headers)
proc newFileResponse*(filename: string, status_code: int = 200, as_attachment: bool = false): FileResponseObj {.exportpy: "FileResponse".} =
  ## FileResponse object
  FileResponseObj(filename: filename, statusCode: status_code, asAttachment: asAttachment)
proc newJsonResponse*(data: JsonNode, status_code: int = 200, headers: PyObject = pyDict()): JsonResponseObj {.exportpy: "JsonResponse".} =
  ## JSON Response object
  JsonResponseObj(data: data, statusCode: status_code, headers: headers)
proc newHtmlResponse*(data: string, status_code: int = 200, headers: PyObject = pyDict()): HtmlResponseObj {.exportpy: "HtmlResponse".} =
  ## HTML Response object
  HtmlResponseObj(data: data, statusCode: status_code, headers: headers)


proc newRequestModelData*(name: string, pyClass: PyObject, fields: seq[tuple[key, val: string]]): RequestModelData {.exportpy: "RequestModelData".} =
  RequestModelData(name: name, fields: fields, pyClass: pyClass)


proc addRequestModelData*(data: RequestModelData) {.exportpy: "register_request_model_data".} =
  requestModelsHidden.requestModels.add(data)


proc path*(self: HttpRequest): string {.exportpy.} = self.path
proc body*(self: HttpRequest): string {.exportpy.} = self.body
proc httpMethod*(self: HttpRequest): string {.exportpy: "http_method".} = self.httpMethod
proc headers*(self: HttpRequest): PPyObject {.exportpy.} = self.headers

proc filename*(self: FileResponseObj): string {.exportpy.} = self.filename
proc asAttachment*(self: FileResponseObj): bool {.exportpy: "as_attachment".} = self.asAttachment

proc data*(self: ResponseObj): string {.exportpy.} = self.data
proc data*(self: JsonResponseObj): JsonNode {.exportpy.} = self.data
proc data*(self: HtmlResponseObj): string {.exportpy.} = self.data

proc statusCode*(self: ResponseObj): int {.exportpy: "status_code".} = self.statusCode
proc statusCode*(self: FileResponseObj): int {.exportpy: "status_code".} = self.statusCode
proc statusCode*(self: JsonResponseObj): int {.exportpy: "status_code".} = self.statusCode
proc statusCode*(self: HtmlResponseObj): int {.exportpy: "status_code".} = self.statusCode

proc headers*(self: ResponseObj): PyObject {.exportpy.} = self.headers
proc headers*(self: JsonResponseObj): PyObject {.exportpy.} = self.headers
proc headers*(self: HtmlResponseObj): PyObject {.exportpy.} = self.headers


proc `$`*(self: Server): string {.exportpy: "__str__".} =
  fmt"Server at http://{self.address}:{self.port}/"


proc startServerPy*(self: Server) {.exportpy: "start".} =
  let
    py = pyBuiltinsModule()
  serve(self.address, self.port):
    discard


proc inspectCallback(callback: PyObject) {.inline.} =
  let inspect = pyImport("inspect")
  if inspect.iscoroutinefunction(callback).to(bool):
    let
      functionName = callback.getAttr("__code__").getAttr("co_name")
      filename = callback.getAttr("__code__").getAttr("co_filename")
      firstLine = callback.getAttr("__code__").getAttr("co_firstlineno")
      hash = callObject(callback.getAttr("__hash__")).to(int64)
    raise newException(
      HpxAppRouteDefect,
      fmt"""Callback function should be sync!
Async function <{functionName} at 0x{toHex(hash, 15)}> at {filename}:{firstLine}"""
    )

proc route*(self: Server, path: string, methods: seq[string]): auto {.exportpy.} =
  ## Registers a new route.
  ## 
  ## You can choose HTTP methods via route("/", ["GET", "POST"])
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    var httpMethods = methods
    for i in 0..<httpMethods.len:
      httpMethods[i] = httpMethods[i].toUpper()
    self.routes.add(initRoute(routeData.path, routeData.purePath, httpMethods, re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc get*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new GET route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["GET"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc post*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new POST route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["POST"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc put*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new PUT route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["PUT"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc delete*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new DELETE route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["DELETE"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc link*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new LINK route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["LINK"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc unlink*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new UNLINK route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["UNLINK"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc purge*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new PURGE route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["PURGE"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc options*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new OPTIONS route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["OPTIONS"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc head*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new HEAD route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["HEAD"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc copy*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new COPY route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["COPY"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc websocket*(self: Server, path: string): auto {.exportpy.} =
  ## Registers a new WEBSOCKET route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    let routeData = handleRoute(path)
    self.routes.add(initRoute(routeData.path, routeData.purePath, @["WEBSOCKET"], re2("^" & routeData.purePath & "$"), callback))
  wrapper


proc middleware*(self: Server): auto {.exportpy.} =
  ## Registers a new MIDDLEWARE route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    self.routes.add(initRoute("", "", @["MIDDLEWARE"], re2("^$"), callback))
  wrapper


proc notfound*(self: Server): auto {.exportpy.} =
  ## Registers a new NOT FOUND route.
  proc wrapper(callback: PyObject) =
    inspectCallback(callback)
    self.routes.add(initRoute("", "", @["NOTFOUND"], re2("^$"), callback))
  wrapper


proc mount*(self: Server, path: string, other: Server) {.exportpy.} =
  ## Registers sub application at `path`
  other.path = path
  self.mounts.add(other)


proc `static`*(self: Server, path: string, directory: string) {.exportpy: "static".} =
  ## Registers public folder
  var
    p = path
  if not p.endsWith("/"):
    p &= "/"
  p &= "{file:path}"
  let routeData = handleRoute(p)
  self.routes.add(initRoute(p, directory, @["STATICFILE"], re2("^" & routeData.purePath & "$"), nil))
