require 'jit/name_resolver'

module Jit

  class BytecodeTransformer

    def initialize
    end

    def transform(bytecode, locals)
      new_bytecode = remove_empty_labels(bytecode)
      new_bytecode = fix_branchunless(new_bytecode)

      stack = []
      bytecode = new_bytecode
      new_bytecode = []
      bytecode.each do |code|
        if code.instance_of?(Array)
          if code.first == :getlocal_OP__WC__0
            code[-1] = NameResolver::resolve_local_var(code.last, locals)
            stack << code
          elsif code.first == :setlocal_OP__WC__0
            code[-1] = NameResolver::resolve_local_var(code.last, locals)
            new_bytecode << code + [{args: stack.pop}]
          elsif [:branchunless, :leave, :branchif].include?(code.first)
            new_bytecode << code + [{args: stack.pop}]
          elsif code.first == :jump
            new_bytecode << code
          elsif code.first == :putobject_OP_INT2FIX_O_1_C_
            stack << [:putobject, 1]
          elsif code.first == :putobject_OP_INT2FIX_O_0_C_
            stack << [:putobject, 0]
          elsif code.first == :dup
            result = stack.pop
            name = "__a#{SecureRandom.uuid}"
            locals << name
            new_bytecode << [:setlocal_OP__WC__0, name, args: result]
            stack << [:getlocal_OP__WC__0, name]
            stack << [:getlocal_OP__WC__0, name]
          elsif code[1].instance_of?(Hash) && code[1][:orig_argc]
            params = code[1][:orig_argc]
            args = (0..params).map do
              stack.pop
            end
            args.reverse!
            stack << code + [{args: args}]
          elsif code.first == :pop
            new_bytecode << stack.pop
          else
            stack << code
          end
        else
          new_bytecode << code
        end
      end

      new_bytecode = fix_double_labels(new_bytecode)
      fix_missing_jumps(new_bytecode)
    end

    private

    def find_label(bytecode, label)
      bytecode.index(label)
    end

    def next_leave(bytecode, index)
      # leave next is like this:
      # [code]
      # :jump(:label_before_leave)
      # or:
      # [code]
      # :leave
      if bytecode[index + 1].nil?
        return false
      end

      if bytecode[index + 1][0] == :leave
        return true
      elsif bytecode[index + 1][0] == :jump
        label = bytecode[index + 1][1]
        label_index = find_label(bytecode, label)
        if bytecode[label_index + 1][0] == :leave
          return true
        end
      end
      false
    end

    def fix_missing_jumps(bytecode)
      new_bytecode = []
      bytecode.each_with_index do |code, i|
        new_bytecode << code
        if code.instance_of?(Array) && (![:jump, :branchif, :branchunless].include?(code.first)) && bytecode[i+1].instance_of?(Symbol)
          new_bytecode << [:jump, bytecode[i+1]]
        end
      end
      new_bytecode
    end

    def remove_empty_labels(bytecode)
      # fix leave, insert return when next op is leave
      new_bytecode = []
      bytecode.each_with_index do |code, index|
        # after leave, code would be dead anyways and llvm does not compile unreachable code!
        if new_bytecode[-1] && new_bytecode[-1][0] == :leave && code.instance_of?(Array)
          next
        end

        new_bytecode << code
        if next_leave(bytecode, index)
          new_bytecode << [:leave]
        end
      end
      new_bytecode
    end

    def fix_branchunless(bytecode)
      new_bytecode = []
      count = 1
      bytecode.each do |code|
        new_bytecode << code
        if code.instance_of?(Array) && [:branchunless, :branchif].include?(code.first)
          symbol = "branch_fix_#{count}".to_sym
          new_bytecode << symbol
          code[2] = symbol
          count += 1
        end
      end
      new_bytecode
    end

    def fix_double_labels(bytecode)
      new_bytecode = []
      rewrite = {}

      bytecode.each_with_index do |code, i|
        if code.instance_of?(Symbol) && bytecode[i+1].instance_of?(Symbol)
          rewrite[code] = bytecode[i+1]
        else
          new_bytecode << code
        end
      end

      new_bytecode.map do |code|
        if code.instance_of?(Array)
          if code.first == :jump && rewrite[code[1]]
            code[1] = rewrite[code[1]]
          elsif [:branchunless, :branchif].include?(code.first) && rewrite[code[1]]
            code[1] = rewrite[code[1]]
          elsif [:branchunless, :branchif].include?(code.first) && rewrite[code[2]]
            code[2] = rewrite[code[2]]
          end
        end

        code
      end
    end

  end

end
