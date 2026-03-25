module Kconv
  module_function

  def toutf8(str)
    str.to_s
  end

  def tosjis(str)
    str.to_s
  end

  def toeuc(str)
    str.to_s
  end
end

class String
  def toutf8
    Kconv.toutf8(self)
  end

  def tosjis
    Kconv.tosjis(self)
  end

  def toeuc
    Kconv.toeuc(self)
  end
end
