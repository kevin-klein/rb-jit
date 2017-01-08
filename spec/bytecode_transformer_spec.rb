require 'spec_helper'


describe Jit::BytecodeTransformer do
  let(:transformer) { Jit::BytecodeTransformer.new }

  describe 'tostring' do

    it 'transforms string concat' do
      code = [
        [:putobject, "test_"],
        [:putobject, 2],
        [:tostring],
        [:concatstrings],
        [:leave]
      ]

      ap code
      result = transformer.transform(code, [])
      ap result.to_s

      expect(result).to eq(
        [[:leave, {:args=>[:concatstrings, {:args=>[[:tostring, {:args=>[:putobject, 2]}], [:putobject, "test_"]]}]}]]
      )
    end

  end

  describe 'extra labels' do

    it 'adds extra labels' do
      code = [
        :label1,
        [:putself],
        [:putobject, 2],
        [:opt_plus],
        [:pop],
        :label2,
        [:leave]
      ]

      result = transformer.transform(code, [])

      expect(result).to eq([
        :label1,
        [
          :opt_plus
        ],
        [
          :jump,
          :label2
        ],
        :label2,
        [
          :leave,
          {
            args: [
              :putobject,
              2
            ]
          }
        ]
      ])
    end

  end

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
