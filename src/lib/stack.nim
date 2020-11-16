import deques
type
  Stack*[T] = Deque[T]


proc newStack[T](): Stack[T] =
  result = initDeque[T]()

proc push[T](stack: Stack[T], elem: T) =
  stack.addFirst(elem)

proc pop[T](stack: Stack[T]): T =
  return stack.popFirst()

proc peek[T](stack: Stack[T]): T =
  return stack.peekFirst()

