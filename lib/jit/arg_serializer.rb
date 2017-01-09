require 'jit/ruby_lib'

module ArgSerializer
  extend self

  INT_FLAG = 0x01

  def serialize(arg)
    case arg
    when Fixnum
      convert_fixnum(arg)
    else
      convert_object(arg)
    end
  end

  def deserialize(arg)
    if arg & INT_FLAG == 1
      (arg >> 1)
    else
      ObjectSpace._id2ref(arg >> 1)
    end
  end

  private

  def convert_object(arg)
    arg.object_id << 1
  end

  def convert_fixnum(arg)
    (arg << 1) | INT_FLAG
  end

end
