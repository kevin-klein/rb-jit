module Jit
  # always int64, even on 32bit
  VALUE   = LLVM::Int64

  QFALSE  = 0
  QTRUE   = 0x14
  QNIL    = 0x08

end
