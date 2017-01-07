require 'spec_helper'

require 'benchmark'

class Test

  def test(n)
    x = 0
    while n > 0
      x = x + n
      n = n + -1
    end
    x
  end

end

describe Jit::JitCompiler do
  let!(:compiler) { Jit::JitCompiler.new }

  describe 'basic compilation' do

    it 'compiles a basic function' do
      compiler.jit(Test.instance_method(:test))

      t = Test.new
      # ap "rb"
      # ap t.test(5)
      # ap "jit"
      # ap t.jit_test(5)
      # raise
      expect(t.jit_test(500000)).to eq(t.test(500000))

      puts Benchmark.realtime {
        t.jit_test(500000)
      }

      puts Benchmark.realtime {
        t.test(500000)
      }

      puts Benchmark.realtime {
        100.times {
          t.jit_test(500000)
        }
      }

      puts Benchmark.realtime {
        100.times {
          t.test(500000)
        }
      }
    end

  end

end
