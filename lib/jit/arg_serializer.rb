module ArgSerializer
  extend self

  INT_FLAG = 0x01

  def serialize(arg)
    case arg
    when Fixnum
      convert_fixnum(arg)
    end
  end

  private

  def convert_fixnum(arg)
    (arg << 1) | INT_FLAG
  end

end
