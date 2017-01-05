require 'spec_helper'


describe Jit::BytecodeTransformer do
  let(:transformer) { Jit::BytecodeTransformer.new }

  describe 'unstackify' do
    it "compresses stack stuff" do
      code = [
        [:getlocal_OP__WC__0, 0],
        [:getlocal_OP__WC__0, 0],
        [:opt_send_without_block, {
          mid: :test,
          flag:  20,
          orig_argc: 1
        }],
        [:leave]
      ]
      locals = ['a']

      result = transformer.transform(code, locals)

      expect(result).to eq([
        [:leave, {
          args: [
            :opt_send_without_block, {
              mid: :test,
              flag: 20,
              orig_argc: 1
            },
            {
              args: [
                [:getlocal_OP__WC__0, nil],
                [:getlocal_OP__WC__0, nil]
              ]
            }
          ]
        }
      ]
    ])
    end
  end

end
