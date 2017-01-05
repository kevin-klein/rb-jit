module Jit

  class JitCompiler

    def initialize
      mod = LLVM::Module.new(method_name.to_s)

      # converts an int64 to a ruby value
      rb_int2inum = mod.functions.add('rb_int2inum', [LLVM::Int64], value)
      # probably 0 if unequal, else 1
      # the return value MIGHT BE Int32!?
      rb_equal = mod.functions.add('rb_equal', [value, value], LLVM::Int64)
      rb_funcallv = mod.functions.add('rb_funcallv', [value, LLVM::Int64, LLVM::Int64, LLVM::Pointer(value)], value)
      rb_intern = mod.functions.add('rb_intern', [LLVM::Pointer(LLVM::Int8)], LLVM::Int64)
      rb_ary_resurrect = mod.functions.add('rb_ary_resurrect', [LLVM::Int64], LLVM::Int64)

      api = {
        rb_int2inum: rb_int2inum,
        rb_equal: rb_equal,
        rb_funcallv: rb_funcallv,
        rb_intern: rb_intern
      }
    end

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

      ap bytecode

      stack = []
      new_bytecode = BytecodeTransformer::transform(bytecode, locals)

      ap new_bytecode

      # remove optional param resolution, we just wrap funcs at the moment
      start_label = params[:opt].try(:last)
      if bytecode.include?(start_label)
        # also remove the default jump mark
        bytecode = bytecode.drop(bytecode.index(start_label) + 1)
      end

      # ap bytecode
      # ap local_stack_vars

      local_llvm_vars = {}
      globals = {}
      blocks = {}
      mod.functions.add(method_name.to_s, [value]*misc[:arg_size], LLVM::Int64) do |function, *args|
        entry = function.basic_blocks.append("entry")
        blocks[:entry] = entry

        last_val = nil

        entry.build do |builder|
          locals.each do |local|
            local_llvm_vars[local] = builder.alloca(value, name=local.to_s)
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
          result = compile_code(code, mod, builder, function, local_llvm_vars, locals, api, globals, blocks, method_name.to_s)
          if result.instance_of?(LLVM::BasicBlock)
            builder.dispose
            last_block = result
            builder = LLVM::Builder.new
            builder.position_at_end(last_block)
          end
        end
        builder.dispose

      end
      mod.dump
      # raise
      mod.verify!

      # raise

      LLVM.init_jit
      engine = LLVM::JITCompiler.new(mod)

      # raise

      p = 3500
      # result = engine.run_function(mod.functions[method_name], p.object_id)

      puts 'normal'
      # p = Page.new
      # p = 21
      # p = Page.new(id: 0)
      # ap p.id
      # id = p.object_id << 1
      id = (p << 1) | 0x01
      ap id
      # ap p.object_id
      # raise
      # id = 21
      # ap test(p)
      page = Page.new
      page_id = page.object_id << 1
      # ap page_id
      func = mod.functions[method_name]
      # ap engine.run_function(func, page_id, id).to_i
      # raise
      # ap (10 << 1) | 0x01
      # ap ObjectSpace._id2ref(engine.run_function(func, page_id, id).to_i)
      # raise
      puts Benchmark.realtime {
        # ap p.object_id
        # ap p
        1000.times { engine.run_function(func, page_id, id) }
      }

      # raise

      # raise

      builder = LLVM::PassManagerBuilder.new
      builder.opt_level = 3

      passm  = LLVM::PassManager.new(engine)
      builder.build(passm)
      passm.run(mod)

      mod.dump

      puts 'optimized'
      func = mod.functions[method_name]
      puts Benchmark.realtime {
        1000.times { engine.run_function(func, page_id, id) }
      }

      puts 'ruby'
      page = Page.new
      puts Benchmark.realtime {
        1000.times { page.test(p) }
      }

      engine.dispose

      # int_result = result.to_i
      # if int_result == 0x14
      #   true
      # elsif int_result == 0
      #   false
      # else
      #   ObjectSpace._id2ref(int_result)
      # end
    end

    def self.compare_truthy(exp, builder)
      # 0x08 nil
      # 0x00 false
      # only nil and false are false
      builder.and(
        builder.icmp(:eq, LLVM::Int64.from_i(0x08), exp),
        builder.icmp(:eq, LLVM::Int64.from_i(0x00), exp))
    end

    def self.compile_code(code, mod, builder, function, local_llvm_vars, locals, api, globals, blocks, name)
      if code.instance_of?(Array)
        if code.first == :setlocal_OP__WC__0
          name = code[1]
          local_var = local_llvm_vars[name]
          arg = code.last[:args]
          arg = compile_code(arg, mod, builder, function, local_llvm_vars, locals, api, globals, blocks, name)
          builder.store(arg, local_var)
        elsif code.first == :branchunless
          arg = code.last[:args]
          arg = compile_code(arg, mod, builder, function, local_llvm_vars, locals, api, globals, blocks, name)

          truthy = compare_truthy(arg, builder)
          jump1 = blocks[code[1]]
          jump2 = blocks[code[2]]

          if jump1.nil?
            raise
          elsif jump2.nil?
            raise
          end

          builder.cond(truthy, jump2, jump1)
        elsif code.first == :getlocal_OP__WC__0
          local_var = local_llvm_vars[code[1]]
          builder.load(local_var)
        elsif code.first == :putself
          local_var = local_llvm_vars['self']
          builder.load(local_var)
        elsif code[1] && code[1].instance_of?(Hash) && code[1][:mid]
          f_name = code[1][:mid]
          if f_name.to_s == name
            # set local vars and jump to entry
            raise
          else
            unless globals[f_name]
              globals[f_name] = mod.globals.add(LLVM::ConstantArray.string(f_name.to_s), f_name) do |var|
                var.linkage = :private
                var.global_constant = true
                var.unnamed_addr = true
                var.initializer = LLVM::ConstantArray.string(f_name.to_s)
              end
            end


            name_pointer = builder.gep(globals[f_name], [LLVM::Int(0), LLVM::Int(0)])
            id = builder.call(api[:rb_intern], name_pointer)

            builder.call(api[:rb_funcallv], call_self, id, LLVM::Int64.from_i(code[1][:orig_argc]), args)
          end
        # elsif code.first == :opt_eq
        #   op1_pointer = builder.gep(stack, [LLVM::Int(0), builder.load(sp)])
        #   dec_stack(builder, sp)
        #
        #   op2_pointer = builder.gep(stack, [LLVM::Int(0), builder.load(sp)])
        #   dec_stack(builder, sp)
        #
        #   eql_result = builder.call(api[:rb_equal], builder.load(op1_pointer), builder.load(op2_pointer))
        #
        #   inc_stack(builder, sp)
        #   pointer = builder.gep(stack, [LLVM::Int(0), builder.load(sp)])
        #   builder.store(eql_result, pointer)
        elsif code.first == :putobject
          if code.last.instance_of?(Fixnum)
            # builder.call(api[:rb_int2inum], LLVM::Int64.from_i(code.last))
            LLVM::Int64.from_i((code.last << 1) | 0x01)
          elsif code.last == false
            LLVM::Int64.from_i(0)
          else
            ap code
            raise
          end
        elsif code.first == :leave
          builder.ret(compile_code(code.last[:args], mod, builder, function, local_llvm_vars, locals, api, globals, blocks, name))
        else
          ap code
          raise
        end
      else
        # function.basic_blocks.append(code.to_s)
        blocks[code]
      end
    end

    def build_args(code, builder)
      size = code[1][:orig_argc]
      args = builder.array_alloca(LLVM::Int64, LLVM::Int64.from_i(size))

      call_self = compile_code(code.last[:args][0], mod, builder, function, local_llvm_vars, locals, api, globals, blocks, name)

      (1..code[1][:orig_argc]).each do |i|
        arg = compile_code(code.last[:args][i], mod, builder, function, local_llvm_vars, locals, api, globals, blocks, name)
        builder.store(arg, builder.gep(args, [LLVM::Int(i - 1)]))
      end
    end

  end

end
