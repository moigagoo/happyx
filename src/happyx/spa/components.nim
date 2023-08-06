## # Components ✨
## 
## Now components fully support in `SPA` projects.
## 
## `SSR` project support components without event handlers and JS features.
## 
import
  # Stdlib
  strformat,
  macros,
  tables,
  # HappyX
  ./renderer,
  ../sugar/[js, style],
  ../core/[exceptions],
  ../private/[macro_utils]


type
  ComponentInfo = object
    extendsOf: string
    fields: seq[string]


var createdComponents {.compileTime.} = newTable[string, ComponentInfo]()


proc replaceSelfStateVal(statement: NimNode) =
  for idx, i in statement.pairs:
    if i.kind == nnkDotExpr:
      if $i.toStrLit == "self":
        statement[idx] = newCall("get", newDotExpr(i[0], i[1]))
      continue
    if i.kind in RoutineNodes:
      continue
    i.replaceSelfStateVal()


proc replaceSuperCall(statement: NimNode, parentComponent, funcName: string, needDiscard: bool = false) =
  ## Replaces super() calls in `statement`
  var superCallsIdx: seq[int] = @[]
  for idx, child in statement.pairs:
    if child.kind == nnkCall and child[0] == ident"super" and child.len == 1:
      superCallsIdx.add(idx)
  
  for i in superCallsIdx:
    if needDiscard:
      statement[i] = newNimNode(nnkDiscardStmt).add(
        newCall("procCall", newDotExpr(newDotExpr(ident"self", ident(parentComponent)), ident(funcName)))
      )
    else:
      statement[i] = newCall(
        "procCall",
        newDotExpr(newDotExpr(ident"self", ident(parentComponent)), ident(funcName))
      )
  
  for child in statement.children:
    if child.kind notin AtomicNodes:
      replaceSuperCall(child, parentComponent, funcName, needDiscard)


macro component*(name, body: untyped): untyped =
  ## Register a new component.
  ## 
  ## Component can have fields
  ## 
  ## ## Basic Usage 🔨
  ## 
  ## .. code-block::nim
  ##    component Component:
  ##      requiredField: int
  ##      optionalField: int = 100
  ##      
  ##      `template`:
  ##        tDiv:
  ##          "requiredField is {self.requiredField}"
  ##        tDiv:
  ##          "optionalField is {self.optionalField}
  ##       
  ##      `script`:
  ##        echo self.requiredField
  ##        echo self.optionalField
  ##      
  ##      `style`:
  ##        """
  ##        div {
  ##          width: {self.requiredField}px;
  ##          height: {self.optionalField}px;
  ##        }
  ##        """
  ## 
  ## ## Pure Css 🎈
  ## 
  ## You can use `buildStyle` macro syntax inside `` `style` ``
  ## 
  ## .. code-block:: nim
  ##    
  ##    component MyComponent:
  ##      ...
  ##      `style` as css:
  ##        tag tDiv:
  ##          background-color: rgb(100, 200, 255)
  ##        tDiv@hover:
  ##          padding: 0 8.px 2.rem 1.em
  ## 
  ## ## Pure JavaScript ✌
  ## 
  ## You also can use `buildJs` macro syntax inside `` `script` ``
  ## 
  ## .. code-block:: nim
  ##    ...
  ##    `script` as js:
  ##      function myFunc(a, b, c):
  ##        echo a, b, c
  ##      
  ##      class MyClass:
  ##        constructor():
  ##          echo "Hi"
  ##      
  ##      var myCls = new MyClass()
  ##      myFunc(1, 2, 3)
  ## 
  ## ## Slots 👨‍🔬
  ## 
  ## Slots is extends your component
  ## 
  ## Declaration:
  ## 
  ## .. code-block::nim
  ##    component Component:
  ##      `template`:
  ##        tDiv:
  ##          slot
  ## 
  ## Usage:
  ## 
  ## .. code-block::nim
  ##    buildHtml:
  ##      component Component(...):
  ##        tDiv(...):
  ##          "This div tag with this text will shown in component slot"
  ## 
  ## ## Inheritance 📦
  ## 
  ## Components may be inherited from other component.
  ## 
  ## Here is minimal example:
  ## 
  ## .. code-block::nim
  ##    component A:
  ##      a: int = 0
  ##      `template`:
  ##        tDiv:
  ##          "Hello, world!"
  ##    component B of A:
  ##      `template`:
  ##        tDiv:
  ##          super()
  ##          {self.a}
  ## 
  let
    componentName =
      if name.kind == nnkIdent:
        $name
      elif name.kind == nnkInfix:
        $name[1]
      else:
        ""
    extendsOf =
      if name.kind == nnkInfix:
        $name[2]
      else:
        ""
  
  if componentName == "":
    throwDefect(
      HpxComponentDefect,
      fmt"component name should be identifier, but got {name.toStrLit}",
      lineInfoObj(name)
    )
  if createdComponents.hasKey(componentName):
    throwDefect(
      HpxComponentDefect,
      fmt"Components with both names is forbidden! component {componentName} has been declared ",
      lineInfoObj(name)
    )
  if extendsOf != "" and not createdComponents.hasKey(extendsOf):
    throwDefect(
      HpxComponentDefect,
      fmt"Component {extendsOf} is not exists!",
      lineInfoObj(name)
    )

  let
    componentNameObj = componentName & "Obj"
    params = newNimNode(nnkRecList)
    initParams = newNimNode(nnkFormalParams)
    initProc = newProc(postfix(ident(fmt"init{componentName}"), "*"))
    initObjConstr = newNimNode(nnkObjConstr).add(
      ident(componentName), newColonExpr(ident(UniqueComponentId), ident(UniqueComponentId))
    )
    beforeStmtList = newStmtList()
    afterStmtList = newStmtList()
    reRenderProc = newProc(
      postfix(ident"reRender", "*"),
      [newEmptyNode(), newIdentDefs(ident"self", ident(componentName))],
      newStmtList(
        newLetStmt(
          ident"tmpData",
          newCall(
            "&",
            newCall("&", newStrLitNode("[data-"), (newDotExpr(ident"self", ident(UniqueComponentId)))),
            newStrLitNode("]")
          )
        ),
        newLetStmt(
          ident"compTmpData",
          newCall(newDotExpr(ident"self", ident"render"))
        ),
        newCall(
          "addArgIter",
          ident"compTmpData",
          newCall("&", newStrLitNode("data-"), newDotExpr(ident"self", ident(UniqueComponentId)))
        ),
        when defined(js):
          newStmtList(
            newVarStmt(ident"_current", newCall("querySelector", ident"document", ident"tmpData")),
            newVarStmt(
              ident"_elements", newCall(newNimNode(nnkBracketExpr).add(ident"newSeq", ident"Element"))
            ),
            newNimNode(nnkForStmt).add(
              ident"tag",
              newDotExpr(
                ident"compTmpData", ident"children"
              ),
              newStmtList(
                newNimNode(nnkIfStmt).add(
                  newNimNode(nnkElifBranch).add(
                    newCall("not", newCall("isNil", ident"_current")),
                    newStmtList(
                      newCall("add", ident"_elements", ident"_current"),
                      newAssignment(
                        ident"_current",
                        newDotExpr(newDotExpr(ident"_current", ident"nextSibling"), ident"Element")
                      )
                    )
                  )
                ),
              )
            ),
            newNimNode(nnkForStmt).add(
              ident"__i",
              newCall("..<", newLit(0), newCall("len", ident"_elements")),
              newStmtList(
                newLetStmt(ident"elem", newNimNode(nnkBracketExpr).add(ident"_elements", ident"__i")),
                newLetStmt(
                  ident"tag",
                  newNimNode(nnkBracketExpr).add(
                    newDotExpr(ident"compTmpData", ident"children"), ident"__i"
                  )
                ),
                newAssignment(
                  newDotExpr(ident"elem", ident"outerHTML"),
                  newCall("cstring", newCall("$", ident"tag"))
                )
              )
            )
          )
        else:
          newCall(
            "add",
            ident"compTmpData",
            newCall(
              "initTag",
              newStrLitNode("script"),
              newCall("@", newNimNode(nnkBracket).add(newCall("textTag",
                newCall("&", newCall(
                    "&", newCall(
                      "fmt", newStrLitNode("document.querySelector('{tmpData}').outerHTML = `")
                    ),
                    newCall("$", ident"compTmpData")
                  ), newStrLitNode("`;")
                )
              )))
            )
          ),
        newCall(newDotExpr(ident"self", ident"rendered"), ident"self")
      ),
      nnkMethodDef
    )
  
  var
    # Components general
    templateStmtList = newStmtList()
    scriptStmtList = newStmtList()
    styleStmtList = newStmtList()
    lifeCyclesDeclare = newStmtList()
    # Functions
    methodsStmtList = newStmtList()
    declareMethodsStmtList = newStmtList()
    # Component constructors
    componentConstructors = newStmtList()
    # Args
    arguments = @[
      newEmptyNode(),
      newIdentDefs(ident"self", ident"BaseComponent"),
      when defined(js):
        newIdentDefs(ident"ev", ident"Event", newNilLit())
      else:
        newIdentDefs(ident"ev", ident"int", newLit(0))
    ]
    usedLifeCycles = {
      "created": false,  # at created
      "updated": false,  # at HTML render end
      "rendered": false,  # at render/reRender end
      "beforeUpdated": false,  # before render/reRender
      "exited": false,
      "pageShow": false,
      "pageHide": false,
    }.newTable()
  
  initParams.add(
    ident(componentName),
    newIdentDefs(ident(UniqueComponentId), bindSym("string"))
  )

  var
    fields: seq[string] = @[]
    fieldTypes: seq[NimNode] = @[]
    initComponentProcedure: seq[NimNode] = @[]
  
  for s in body.children:
    if s.kind in [nnkCall, nnkCommand, nnkInfix, nnkPrefix]:
      # Private field
      if s[0] != ident"constructor" and s[0].kind == nnkIdent and s.len == 2 and s[^1].kind == nnkStmtList and s[^1].len == 1:
        # Extract default value and field type
        let (fieldType, defaultValue) =
          if s[^1][0].kind != nnkAsgn:
            (s[^1][0], newEmptyNode())
          else:  # assignment statement
            (s[^1][0][0], s[^1][0][1])
        params.add(newNimNode(nnkIdentDefs).add(
          s[0],
          newCall(
            bindSym("[]", brForceOpen), ident"State", fieldType
          ),
          newEmptyNode()
        ))
        initParams.add(newNimNode(nnkIdentDefs).add(
          s[0], fieldType, defaultValue
        ))
        initObjConstr.add(newColonExpr(s[0], newCall("remember", s[0])))
        fields.add($(s[0]))
        fieldTypes.add(fieldType)
      
      # Public field
      elif s.kind == nnkPrefix and s[0] == ident"*" and s[1].kind == nnkIdent and s[2].len == 1:
        # Extract field type and default value
        let (fieldType, defaultValue) =
          if s[^1][0].kind != nnkAsgn:
            (s[^1][0], newEmptyNode())
          else:  # assignment statement
            (s[^1][0][0], s[^1][0][1])
        params.add(newNimNode(nnkIdentDefs).add(
          postfix(s[1], "*"),
          newCall(
            bindSym("[]", brForceOpen), ident"State", fieldType
          ),
          newEmptyNode()
        ))
        initParams.add(newNimNode(nnkIdentDefs).add(
          s[1], fieldType, defaultValue
        ))
        initObjConstr.add(newColonExpr(s[1], newCall("remember", s[1])))
        fields.add($(s[1]))
        fieldTypes.add(fieldType)
      
      # Constructors
      elif s.kind == nnkCall and s[0] == ident"constructor" or (s[0].kind == nnkObjConstr and s[0][0] == ident"constructor"):
        # Ignore constructorBody comments and insert self declaration
        var
          constructorBody = s[1]
          i = 0
        for child in constructorBody.children:
          if child.kind == nnkCommentStmt:
            inc i
            continue
          else:
            var x = newCall(fmt"init{componentName}", ident(UniqueComponentId))
            constructorBody.insert(
              i,
              newVarStmt(
                ident"self",
                x
              )
            )
            initComponentProcedure.add(x)
            constructorBody.add(newNimNode(nnkReturnStmt).add(ident"self"))
            break
        # Constructor without arguments
        if s[0].kind == nnkIdent:
          componentConstructors.add(
            newProc(
              postfix(ident(fmt"constructor_{componentName}"), "*"),
              [ident(componentName), newIdentDefs(ident(UniqueComponentId), bindSym("string"))],
              constructorBody
            )
          )
        # Constructor with arguments
        else:
          var args = @[ident(componentName), newIdentDefs(ident(UniqueComponentId), bindSym("string"))]
          for arg in s[0].children:
            if arg.kind == nnkExprColonExpr:
              args.add(newIdentDefs(arg[0], arg[1]))
          componentConstructors.add(
            newProc(
              postfix(ident(fmt"constructor_{componentName}"), "*"),
              args,
              constructorBody
            )
          )
      
      # funcs, procs, methods, iterators, converters
      elif s[0].kind == nnkBracket and s[0][0] == ident"methods" and s.len == 2 and s[1].kind == nnkStmtList:
        for statement in s[1]:
          if statement.kind in [nnkProcDef, nnkMethodDef, nnkIteratorDef, nnkConverterDef]:
            statement[3].insert(1, newIdentDefs(ident"self", ident(componentName)))
            methodsStmtList.add(statement)
            var declaration = statement.copy()
            declaration.body = newEmptyNode()
            declareMethodsStmtList.add(declaration)
          else:
            throwDefect(
              HpxComponentDefect,
              fmt"only procedures, methods, iterators and converters available here. ",
              lineInfoObj(statement)
            )
    
      # template, style or script
      elif s[0].kind == nnkAccQuoted or s.kind == nnkInfix and s[1].kind == nnkAccQuoted:
        var
          asType = ""
          acc: NimNode = nil
        if s[0].kind == nnkAccQuoted:
          acc = s[0]
        else:
          acc = s[1]
          asType = $s[2]
        case $acc
        of "template":
          # Component template
          s[^1].replaceSuperCall(extendsOf, "renderTag")
          templateStmtList = newStmtList(
            newAssignment(
              ident"result",
              newCall(
                "buildComponentHtml",
                ident(componentName),
                s[^1]
              )
            )
          )
        of "style":
          # Component styles
          if asType != "":
            # Pure CSS on as css
            if asType.toLower() != "css":
              throwDefect(
                HpxComponentDefect,
                fmt"style as {asType} is invalid. Should be 'style as css'! ",
                lineInfoObj(s)
              )
            let css = getAst(buildStyle(s[^1]))[1]
            let str = ($css).replace(
              re"^([\S ]+?) *\{(?im)", "$1[data-<self.uniqCompId>]{"
            ).replace(re"(^ *|\{ *|\n *)\}(?im)", "$1}")
            styleStmtList = newStmtList(
              newAssignment(
                ident"result",
                newCall("fmt", newStrLitNode(str), newLit('<'), newLit('>'))
              )
            )
          elif s[^1][0].kind in [nnkStrLit, nnkTripleStrLit]:
            # String CSS
            let str = ($s[1][0]).replace(
              re"([\S ]+?) *\{(?![ \S]+?\}\s*[;])", "$1[data-{self.uniqCompId}] {{"
            ).replace(re"(\n[ \t]+)\}", "$1}}")
            styleStmtList = newStmtList(
              newAssignment(
                ident"result",
                newCall("fmt", newStrLitNode(str))
              )
            )
          elif s[^1][0].kind == nnkCall and s[^1][0][0].kind == nnkIdent and $s[^1][0][0] == "buildStyle":
            # Pure CSS
            let css = getAst(buildStyle(s[^1][0][1]))[1]
            let str = ($css).replace(
              re"^([\S ]+?) *\{(?im)", "$1[data-<self.uniqCompId>]{"
            ).replace(re"(^ *|\{ *|\n *)\}(?im)", "$1}")
            styleStmtList = newStmtList(
              newAssignment(
                ident"result",
                newCall("fmt", newStrLitNode(str), newLit('<'), newLit('>'))
              )
            )
          else:
            throwDefect(
              HpxComponentDefect,
              "unknown style syntax ",
              lineInfoObj(s)
            )
        of "script":
          # Component main script
          if asType != "":
            # Pure JavaScript
            when not defined(js):
              throwDefect(
                HpxComponentDefect,
                "as js available only on JS backend ",
                lineInfoObj(s)
              )
            if asType.toLower() != "js":
              throwDefect(
                HpxComponentDefect,
                fmt"style as {asType} is invalid. Should be 'style as css'! ",
                lineInfoObj(s)
              )
            scriptStmtList = newStmtList(
              getAst(buildJs(s[^1]))
            )
          else:
            s[^1].replaceSelfComponent(ident(componentName), convert = false, is_constructor = true)
            scriptStmtList = s[^1]
            scriptStmtList.insert(0, newAssignment(ident"enableRouting", newLit(false)))
            scriptStmtList.add(newAssignment(ident"enableRouting", newLit(true)))
        else:
          let structure = $s[0]
          throwDefect(
            HpxComponentDefect,
            fmt"undefined component structure ({structure}).",
            lineInfoObj(s)
          )
      
      elif s.kind == nnkPrefix and s[0] == ident"@":
        if s.len == 3 and s[1].kind == nnkIdent:
          # Component life cycles
          let key = $s[1]
          if usedLifeCycles.hasKey(key) and not usedLifeCycles[key]:
            var lambdaBody = s[2]
            lambdaBody.replaceSelfComponent(ident(componentName), convert = false, is_constructor = true)
            lifeCyclesDeclare.insert(0, newAssignment(
              newDotExpr(ident"result", ident(key)),
              newLambda(lambdaBody, arguments)
            ))
            usedLifeCycles[key] = true
          elif not usedLifeCycles.hasKey(key):
            throwDefect(
              HpxComponentDefect,
              fmt"Wrong component event ({key})",
              lineInfoObj(s)
            )
      else:
        throwDefect(
          HpxComponentDefect,
          "Unknown component declaration syntax ",
          lineInfoObj(s)
        )
  
  for key in usedLifeCycles.keys:
    if not usedLifeCycles[key]:
      lifeCyclesDeclare.insert(0, newAssignment(
        newDotExpr(ident"result", ident(key)),
        newLambda(newStmtList(discardStmt), arguments)
      ))
  
  initProc.params = initParams
  initProc.body = newStmtList(
    newAssignment(ident"result", initObjConstr),
    lifeCyclesDeclare
  )

  # Life cycles
  beforeStmtList.add(
    # Is created
    newNimNode(nnkIfStmt).add(newNimNode(nnkElifBranch).add(
      newCall("==", newDotExpr(ident"self", ident"isCreated"), newLit(false)),
      newStmtList(
        newCall(newDotExpr(ident"self", ident"created"), ident"self"),
        newAssignment(
          newDotExpr(ident"self", ident"isCreated"),
          newLit(true)
        )
      )
    ))
  ).add(
    # beforeUpdated
    newCall(newDotExpr(ident"self", ident"beforeUpdated"), ident"self")
  )
  afterStmtList.add(
    newCall(newDotExpr(ident"self", ident"rendered"), ident"self")
  )

  createdComponents[componentName] = ComponentInfo(extendsOf: extendsOf, fields: fields)

  if extendsOf != "":
    scriptStmtList.replaceSuperCall(extendsOf, "script")
  
  var idx = 0
  for field in fields:
    for i in initComponentProcedure:
      i.add(newNimNode(nnkExprEqExpr).add(
        ident(field), newCall("default", fieldTypes[idx])
      ))
    inc idx

  result = newStmtList(
    newNimNode(nnkTypeSection).add(
      newNimNode(nnkTypeDef).add(
        postfix(ident(componentNameObj), "*"),  # componentName
        newEmptyNode(),
        newNimNode(nnkObjectTy).add(
          newEmptyNode(),  # no pragma
          if extendsOf == "":
            newNimNode(nnkOfInherit).add(ident"BaseComponentObj")
          else:
            newNimNode(nnkOfInherit).add(ident(extendsOf)),
          params
        )
      ),
      newNimNode(nnkTypeDef).add(
        postfix(ident(componentName), "*"),  # componentName
        newEmptyNode(),
        newNimNode(nnkRefTy).add(ident(componentNameObj))
      )
    ),
    declareMethodsStmtList,
    initProc,
    componentConstructors,
    reRenderProc,
    newProc(
      ident"script",
      [
        newEmptyNode(),
        newIdentDefs(ident"self", ident(componentName))
      ],
      if scriptStmtList.len != 0:
        scriptStmtList
      elif extendsOf == "":
        discardStmt
      else:
        newCall("procCall", newDotExpr(newDotExpr(ident"self", ident(extendsOf)), ident"script")),
      pragmas =
        when defined(js):
          newEmptyNode()
        else:
          newNimNode(nnkPragma).add(ident"gcsafe")
    ),
    newProc(
      ident"style",
      [
        ident"string",
        newIdentDefs(ident"self", ident(componentName))
      ],
      if styleStmtList.len != 0 and extendsOf == "":
        styleStmtList
      elif styleStmtList.len != 0 and extendsOf != "":
        newStmtList(
          styleStmtList,
          newAssignment(
            ident"result",
            newCall(
              "&",
              newCall("procCall", newDotExpr(newDotExpr(ident"self", ident(extendsOf)), ident"style")),
              ident"result"
            )
          )
        )
      elif extendsOf == "":
        newStrLitNode("")
      else:
        newCall("procCall", newDotExpr(newDotExpr(ident"self", ident(extendsOf)), ident"style")),
      pragmas =
        when defined(js):
          newEmptyNode()
        else:
          newNimNode(nnkPragma).add(ident"gcsafe")
    ),
    newProc(
      postfix(ident"renderTag", "*"),
      [ident"TagRef", newIdentDefs(ident"self", ident(componentName))],
      newStmtList(
        if templateStmtList.len != 0:
          templateStmtList
        elif extendsOf != "":
          newAssignment(
            ident"result",
            newCall("procCall", newDotExpr(newDotExpr(ident"self", ident(extendsOf)), ident"renderTag"))
          )
        else:
          newAssignment(
            ident"result",
            newCall(
              "buildComponentHtml",
              ident(componentName),
              newStmtList()
            )
          )
      )
    ),
    newProc(
      postfix(ident"render", "*"),
      [
        ident"TagRef",
        newIdentDefs(ident"self", ident(componentName))
      ],
      newStmtList(
        newCall("add", ident"currentComponentsList", ident"self"),
        newAssignment(ident"currentComponent", newDotExpr(ident"self", ident(UniqueComponentId))),
        newCall("script", ident"self"),
        beforeStmtList,
        newAssignment(
          ident"result", newCall("renderTag", ident"self")
        ),
        newCall(
          "add",
          ident"result",
          newCall("initTag", newStrLitNode("style"), newCall("@", newNimNode(nnkBracket).add(
            newCall("textTag", newCall("style", ident"self"))
          )))
        ),
        afterStmtList,
        newAssignment(ident"currentComponent", newStrLitNode("")),
      ),
      nnkMethodDef,
      pragmas =
        when defined(js):
          newEmptyNode()
        else:
          newNimNode(nnkPragma).add(ident"gcsafe")
    ),
    methodsStmtList,
  )
