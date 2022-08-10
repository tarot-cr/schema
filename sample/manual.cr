require "../src/tarot/schema"

class Int32Schema < Tarot::Schema
  field x : Int32, converter: NumericConverter(Int32)
end


x = Int32Schema.new(x: 1_i32)
x.valid?
pp x

record Point, x : Int64, y : Int64 do
  def to_json(builder : JSON::Builder)
    builder.array do
      builder.scalar(x)
      builder.scalar(y)
    end
  end

  module Converter
    def self.from(json : JSON::Any, hint = nil)
      arr = json.as_a?

      if arr && arr.size == 2 && arr.all?(&.as_i64?)
        Point.new(arr[0].as_i64, arr[1].as_i64)
      else
        raise Tarot::Schema::InvalidConversionError.new
      end
    end
  end
end

class ArrayPointSchema < Tarot::Schema
  field points : Array(Point), converter: ArrayConverter(Point::Converter)
end

schema = ArrayPointSchema.from(points: [[1,2], [3,4]])
pp schema.to_json