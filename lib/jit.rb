require "jit/version"

require 'fiddle'
library = Fiddle::Handle.new('ext/target/release/libext.so', Fiddle::RTLD_NOW | Fiddle::RTLD_GLOBAL)

# puts library['opt_plus']
# puts Fiddle::Handle.sym('opt_plus')

require 'llvm/core'
require 'llvm/analysis'
require 'llvm/transforms/builder'
require 'llvm/transforms/ipo'
require "llvm/execution_engine"
require 'jit/llvm_patches'

require 'jit/values'
require 'jit/bytecode_transformer'
require 'jit/arg_serializer'
require 'jit/jit_compiler'

module Jit
  # Your code goes here...
end
