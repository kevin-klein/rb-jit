require 'spec_helper'

require 'benchmark'

class Test

  def test(n)
    x = 0
    while n > 0
      x = x + n
      n = n - 1
    end
    x
  end

  def string_test(s)
    "test_#{s}"
  end

end

describe Jit::JitCompiler do
  let!(:compiler) { Jit::JitCompiler.new }

  describe 'strings' do

    it 'compiles a string' do
      compiler.jit(Test.instance_method(:string_test))

      t = Test.new

      expect(t.string_test('hello')).to eq(t.jit_string_test('hello'))
    end

  end

  describe 'basic compilation' do

    it 'compiles a basic function' do
      compiler.jit(Test.instance_method(:test))

      t = Test.new

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
