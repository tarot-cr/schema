require "../src/tarot/schema"

class JSONAPIDocument(T) < Tarot::Schema
  class SingleDataRecord(U) < Tarot::Schema
    field type : String
    field id : String?

    # `type` is used as hint for the factory of U
    field attributes : U, hint: "type"
  end

  field data : SingleDataRecord(T) | Array(SingleDataRecord(T))?
  # do not use the reserved `errors` name, instead name it data_errors
  field data_errors : JSON::Any?, key: "errors"

  # Quickly and ugly rule following this:
  # https://jsonapi.org/format/#document-top-level
  rule "_root", "must_contains_data_or_errors_only" do
    # data OR errors.
    data.nil? != data_errors.nil?
  end

  # Helpers
  def data_array
    data.as(Array)
  end

  def single_record
    (is_array? ? data.try &.first : data).as(T)
  end
end

abstract class EventBase < Tarot::Schema
  abstract def activate!

  factory "_hint_", {
    /^mouse/ => MouseEvent, # delegate to the factory of mouse event
    "visibility_changed" => VisibilityChangedEvent
  }
end

# Example of custom structure used below.

record Point, x : Int64, y : Int64 do
  def to_json(builder : JSON::Builder)
    builder.array do
      builder.scalar(x)
      builder.scalar(y)
    end
  end

  module Converter
    def self.from(json : JSON::Any, hint = nil) : Point
      arr = json.as_a?

      if arr && arr.size == 2 && arr.all?(&.as_i64?)
        Point.new(arr[0].as_i64, arr[1].as_i64)
      else
        raise Tarot::Schema::InvalidConversionError.new
      end
    end
  end

end

abstract class MouseEvent < EventBase
  field cursor : Point, converter: Point::Converter

  def x
    cursor.x
  end

  def y
    cursor.y
  end

  factory "_hint_", {
    "mouse_clicked" => MouseClickedEvent,
    "mouse_entered" => MouseEnteredEvent
  }
end

class MouseClickedEvent < MouseEvent
  field double_click : Bool

  def activate!
    if double_click
      puts "pwet pwet at #{x} #{y}"
    else
      puts "pwet at #{x} #{y}"
    end
  end
end

class MouseEnteredEvent < MouseEvent
  field frame : String

  def activate!
    puts "enter #{frame} at #{x}, #{y}"
  end
end

class VisibilityChangedEvent < EventBase
  field visible : Bool

  def activate!
    if visible
      puts "I'm visible now!"
    else
      puts "I'm invisible now!"
    end
  end
end

TEST_CASES = [
  %({
    "data": [
      {
        "id": "1",
        "type": "mouse_clicked",
        "attributes": {
          "cursor": [123, 821],
          "double_click": true
        }
      },
      {
        "id": "2",
        "type": "mouse_entered",
        "attributes": {
          "cursor": [100, 123],
          "frame": "A footbal field"
        }
      }
    ]
  })
]

# Import the document.
result = JSONAPIDocument(EventBase).from(
  JSON.parse(TEST_CASES[0])
)

unless result.valid?
  pp result.errors
  raise "error"
end

pp result

puts result.to_json

result.data.as(Array).each(&.attributes.activate!)



