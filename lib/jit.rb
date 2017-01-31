require "jit/version"

require "awesome_print"
require 'fiddle'
library = Fiddle::Handle.new('ext/target/release/libext.so', Fiddle::RTLD_NOW | Fiddle::RTLD_GLOBAL)

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

  module TracingJit
    extend self
    @cache = {}
    @compiled = []

    attr_reader :cache
    attr_reader :compiled
  end

  # Your code goes here...
end

trace = TracePoint.new(:call) do |tp|
  class_name = tp.defined_class.name
  if class_name
    name = "#{class_name}/#{tp.method_id}"
    unless Jit::TracingJit.compiled.include?(name)
      Jit::TracingJit.cache[name] ||= 0
      Jit::TracingJit.cache[name] += 1

      if Jit::TracingJit.cache[name] > 100

      end
    end
  end
end

trace.enable
