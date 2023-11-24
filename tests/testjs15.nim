import ../src/happyx


component withPresets:
  n: int = 5
  s: string = $n
  `template`:
   {self.s}


component withSlot:
  s: string = $1
  `template`:
    "The number is {self.s}, and the slot is "
    slot



importComponent "example.hpx" as Example
importComponent "button.hpx" as ButtonExample


appRoutes("app"):
  "/issue183":
    tDiv: component withPresets
    tDiv: component withPresets(s= "I better not be 5")

    if 1 == 2:
      "Hello!"
    elif 1 == 3:
      "Bye!"
    else:
      "Oops!"
    
    nim:
      let age = 20
    
    tDiv:
      "Example component 5\n    !!!!\n"
      if age < 20:
        tDiv:
          "You\'re young!\n"
      elif age < 35:
        tDiv:
          "You\'re already young!\n"
      else:
        tDiv:
          "You\'re old!\n"
      for i in [1, 2, 3, 4]:
        tDiv:
          "{i}\n"
      nim:
        var x = 10
      "{x}\n"
      while x > 0:
        tDiv("style" = "display: flex; gap: .2rem;"):
          "{x}\n"
          nim:
            dec x
      tDiv:
        "123213213213\n"
  
  "/issue184":
    var x = buildHtml(tDiv):
      "Hello?"
    buildHtml:
      x
      x
      x:
        "world!"
  
  "/issue185":
    tDiv:
      component withSlot(): "one"
    tDiv:
      component withSlot($7): "seven"
    tDiv:
      withSlot(): "one"
    #tDiv:
      #withSlot($7): "seven"
