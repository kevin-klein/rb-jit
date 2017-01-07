require 'spec_helper'

describe ArgSerializer do

  describe 'fixnums' do

    it 'converts a fixnum' do
      n = 1

      result = ArgSerializer.serialize(n)

      expect(result).to eq(3)
    end

    it 'converts 0' do
      n = 0

      result = ArgSerializer.serialize(n)

      expect(result).to eq(1)
    end

  end

end
