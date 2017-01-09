require 'ffi'

module RubyLib
  extend FFI::Library
  ffi_lib 'libruby.so'
  attach_function :rb_intern, [:string], :int
  attach_function :rb_str_new_cstr, [:string], :int
  attach_function :rb_str_new, [:string, :int], :int
end
