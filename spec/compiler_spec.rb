require 'spec_helper'

class Test

  def test(n)
    n + 1
  end

end

describe Jit::JitCompiler do
  let!(:compiler) { Jit::JitCompiler.new }

  describe 'basic compilation' do

    it 'compiles a basic function' do
      t = Test.new

      func = compiler.jit(t.method(:test))

      puts func
    end

  end

end
