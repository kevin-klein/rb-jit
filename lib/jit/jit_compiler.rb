require 'jit/values'
require 'jit/ruby_lib'

require "awesome_print"

require 'logger'

module Jit

  class JitCompiler

    def initialize
      @mod = LLVM::Module.new("rb-jit")

      # 0 if unequal, else 1
      @rb_equal          = @mod.functions.add('rb_equal', [VALUE, VALUE], LLVM::Int64)
      # 
      @rb_funcallv       = @mod.functions.add('rb_funcallv', [VALUE, VALUE, LLVM::Int64, LLVM::Pointer(VALUE)], VALUE)
      @rb_obj_as_string  = @mod.functions.add('rb_obj_as_string', [VALUE], VALUE)
      @rb_ary_resurrect  = @mod.functions.add('rb_ary_resurrect', [VALUE], VALUE)
      @opt_plus          = @mod.functions.add('opt_plus', [VALUE, VALUE], VALUE)
      @opt_minus         = @mod.functions.add('opt_minus', [VALUE, VALUE], VALUE)
      @opt_mult          = @mod.functions.add('opt_mult', [VALUE, VALUE], VALUE)
      @opt_div           = @mod.functions.add('opt_div', [VALUE, VALUE], VALUE)
      @concat_string_literals = @mod.functions.add('concat_string_literals', [LLVM::Int64, LLVM::Pointer(VALUE)], VALUE)

      @opt_gt            = @mod.functions.add('opt_gt', [VALUE, VALUE], VALUE)

      @logger = Logger.new(STDOUT)
      @logger.level = Logger::INFO


      @builder = LLVM::PassManagerBuilder.new
      @builder.opt_level = 3

      LLVM.init_jit
      @engine = LLVM::JITCompiler.new(@mod)

      @pass_manager  = LLVM::PassManager.new(@engine)
      @builder.build(@pass_manager)
    end

    attr_reader :mod

    def jit(method)
      instructions = RubyVM::InstructionSequence.of(method)
      method_name = method.name

      data = instructions.to_a

      magic           = data[0]
      major_version   = data[1]
      minor_version   = data[2]
      format_type     = data[3]
      misc            = data[4]
      # adding self
      misc[:arg_size] += 1
      label           = data[5]
      path            = data[6]
      absolute_path   = data[7]
      first_lineno    = data[8]
      type            = data[9]

      # vars are resolved backwards and -1
      locals            = ['self'] + data[10]
      local_stack_vars  = locals.last(misc[:arg_size])

      # contains jump labels which are jumped to if optional vars exist
      params          = data[11]
      catch_table     = data[12]
      bytecode        = data[13]
      param_names     = locals.first(misc[:arg_size])

      bytecode = bytecode.select do |code|
        if code.instance_of?(Fixnum)
          false
        else
          code[0] != :trace
        end
      end

      # @logger.info(bytecode.to_s)
      ap bytecode

      new_bytecode = BytecodeTransformer.new.transform(bytecode, locals)

      # @logger.info(new_bytecode)
      ap new_bytecode

      # remove optional param resolution, we just wrap funcs at the moment
      start_label = params[:opt]&.last
      if bytecode.include?(start_label)
        # also remove the default jump mark
        bytecode = bytecode.drop(bytecode.index(start_label) + 1)
      end

      # ap bytecode
      # ap local_stack_vars

      local_llvm_vars = {}
      globals = {}
      blocks = {}
      @mod.functions.add(method_name.to_s, [VALUE]*misc[:arg_size], LLVM::Int64) do |function, *args|
        entry = function.basic_blocks.append("entry")
        blocks[:entry] = entry

        last_val = nil

        entry.build do |builder|
          locals.each do |local|
            local_llvm_vars[local] = builder.alloca(VALUE, name=local.to_s)
          end

          param_names.each_with_index do |param, index|
            args[index].name = param.to_s
            store = builder.store(args[index], local_llvm_vars[param])
          end
        end

        new_bytecode.each do |code|
          if code.instance_of?(Symbol)
            blocks[code] = function.basic_blocks.append(code.to_s)
          end
        end

        last_block = entry
        builder = LLVM::Builder.new
        builder.position_at_end(last_block)
        new_bytecode.each do |code|
          result = compile_code(code, mod, builder, function, local_llvm_vars, locals, globals, blocks, method_name.to_s)
          if result.instance_of?(LLVM::BasicBlock)
            builder.dispose
            last_block = result
            builder = LLVM::Builder.new
            builder.position_at_end(last_block)
          end
        end
        builder.dispose

      end
      @mod.dump
      @mod.verify!

      @pass_manager.run(@mod)
      @mod.dump

      cls = method.owner

      e = @engine
      func = @mod.functions[method_name.to_s]
      cls.class_eval do
        define_method("jit_#{method_name}") do |*args|
          args = args.map do |arg|
            ArgSerializer.serialize(arg)
          end

          result = e.run_function(func, ArgSerializer.serialize(self), *args).to_i
          ArgSerializer.deserialize(result)
        end
      end

      # raise

      # raise

      # p = 3500
      # result = engine.run_function(mod.functions[method_name], p.object_id)

      # puts 'normal'
      # # p = Page.new
      # # p = 21
      # # p = Page.new(id: 0)
      # # ap p.id
      # # id = p.object_id << 1
      # id = (p << 1) | 0x01
      # puts id
      # # ap p.object_id
      # # raise
      # # id = 21
      # # ap test(p)
      # page = Page.new
      # page_id = page.object_id << 1
      # # ap page_id
      # func = mod.functions[method_name]
      # # ap engine.run_function(func, page_id, id).to_i
      # # raise
      # # ap (10 << 1) | 0x01
      # # ap ObjectSpace._id2ref(engine.run_function(func, page_id, id).to_i)
      # # raise
      # puts Benchmark.realtime {
      #   # ap p.object_id
      #   # ap p
      #   1000.times { engine.run_function(func, page_id, id) }
      # }

      # raise

      # raise
      #
      # @mod.dump
      #
      # puts 'optimized'
      # func = mod.functions[method_name]
      # puts Benchmark.realtime {
      #   1000.times { engine.run_function(func, page_id, id) }
      # }
      #
      # puts 'ruby'
      # page = Page.new
      # puts Benchmark.realtime {
      #   1000.times { page.test(p) }
      # }
      #
      # engine.dispose

      # int_result = result.to_i
      # if int_result == 0x14
      #   true
      # elsif int_result == 0
      #   false
      # else
      #   ObjectSpace._id2ref(int_result)
      # end

    end

    def compare_truthy(exp, builder)
      # 0x08 nil
      # 0x00 false
      # only nil and false are false
      builder.and(
        builder.icmp(:ne, LLVM::Int64.from_i(0x08), exp),
        builder.icmp(:ne, LLVM::Int64.from_i(0x00), exp))
    end

    def compile_code(code, mod, builder, function, local_llvm_vars, locals, globals, blocks, name)
      if code.instance_of?(Array)
        if code.first == :setlocal_OP__WC__0
          name = code[1]
          local_var = local_llvm_vars[name]
          arg = code.last[:args]
          arg = compile_code(arg, mod, builder, function, local_llvm_vars, locals, globals, blocks, name)
          builder.store(arg, local_var)
        elsif code.first == :jump
          jump = blocks[code[1]]
          builder.br(jump)
        elsif code.first == :branchunless
          arg = code.last[:args]
          arg = compile_code(arg, mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

          truthy = compare_truthy(arg, builder)
          jump1 = blocks[code[1]]
          jump2 = blocks[code[2]]

          builder.cond(truthy, jump2, jump1)
        elsif code.first == :tostring
          arg = code.last[:args]
          arg = compile_code(arg, mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

          builder.call(@rb_obj_as_string, arg)
        elsif code.first == :branchif
          arg = code.last[:args]
          arg = compile_code(arg, mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

          truthy = compare_truthy(arg, builder)
          jump1 = blocks[code[1]]
          jump2 = blocks[code[2]]

          builder.cond(truthy, jump1, jump2)
        elsif code.first == :getlocal_OP__WC__0
          local_var = local_llvm_vars[code[1]]
          builder.load(local_var)
        elsif code.first == :putself
          local_var = local_llvm_vars['self']
          builder.load(local_var)
        elsif code.first == :opt_plus
          call_self = compile_code(code.last[:args][0], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)
          arg = compile_code(code.last[:args][1], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

          builder.call(@opt_plus, call_self, arg)
        elsif code.first == :opt_minus
          call_self = compile_code(code.last[:args][0], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)
          arg = compile_code(code.last[:args][1], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

          builder.call(@opt_minus, call_self, arg)
        elsif code.first == :opt_div
          call_self = compile_code(code.last[:args][0], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)
          arg = compile_code(code.last[:args][1], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

          builder.call(@opt_div, call_self, arg)
        elsif code.first == :opt_mult
          call_self = compile_code(code.last[:args][0], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)
          arg = compile_code(code.last[:args][1], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

          builder.call(@opt_mult, call_self, arg)
        elsif code.first == :opt_gt
          call_self = compile_code(code.last[:args][0], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)
          arg = compile_code(code.last[:args][1], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

          builder.call(@opt_gt, call_self, arg)
        elsif code.first == :concatstrings
          args = builder.array_alloca(LLVM::Int64, LLVM::Int64.from_i(code[1]))

          args_count = code[1]-1
          (0..args_count).each do |i|
            arg = compile_code(code.last[:args][i], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)
            builder.store(arg, builder.gep(args, [LLVM::Int(args_count-i)]))
          end

          builder.call(@concat_string_literals, LLVM::Int64.from_i(code[1]), args)
        elsif code[1] && code[1].instance_of?(Hash) && code[1][:mid]
          f_name = code[1][:mid]
          if f_name.to_s == name
            # set local vars and jump to entry
            raise
          else
            # unless globals[f_name]
            #   globals[f_name] = mod.globals.add(LLVM::ConstantArray.string(f_name.to_s), f_name) do |var|
            #     var.linkage = :private
            #     var.global_constant = true
            #     var.unnamed_addr = true
            #     var.initializer = LLVM::ConstantArray.string(f_name.to_s)
            #   end
            # end

            # name_pointer = builder.gep(globals[f_name], [LLVM::Int(0), LLVM::Int(0)])
            # id = builder.call(@rb_intern, name_pointer)
            call_self = compile_code(code.last[:args][0], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

            id = LLVM::Int64.from_i(RubyLib.rb_intern(f_name.to_s))

            args = build_args(code, mod, builder, function, local_llvm_vars, locals, globals, blocks, name)

            builder.call(@rb_funcallv, call_self, id, LLVM::Int64.from_i(code[1][:orig_argc]), args)
          end
        elsif code.first == :putobject
          if code.last.instance_of?(Fixnum)
            LLVM::Int64.from_i((code.last << 1) | 0x01)
          elsif code.last == false
            LLVM::Int64.from_i(0)
          elsif code.last.instance_of?(String)
            LLVM::Int64.from_i(ArgSerializer.serialize(code.last))
          else
            ap code
            raise
          end
        elsif code.first == :putnil
          LLVM::Int64.from_i(QNIL)
        elsif code.first == :leave
          builder.ret(compile_code(code.last[:args], mod, builder, function, local_llvm_vars, locals, globals, blocks, name))
        else
          ap code
          raise
        end
      else
        # function.basic_blocks.append(code.to_s)
        blocks[code]
      end
    end

    def build_args(code, mod, builder, function, local_llvm_vars, locals, globals, blocks, name, start: 1)
      size = code[1][:orig_argc]
      args = builder.array_alloca(LLVM::Int64, LLVM::Int64.from_i(size))

      (start..code[1][:orig_argc]).each do |i|
        arg = compile_code(code.last[:args][i], mod, builder, function, local_llvm_vars, locals, globals, blocks, name)
        builder.store(arg, builder.gep(args, [LLVM::Int(i - 1)]))
      end

      args
    end

  end

end
