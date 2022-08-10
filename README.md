# Tarot Schema Validation

Schema validation for JSON structure in Crystal. Part of the Tarot project.

Wild features include:

- Type and presence validation + custom rules definition
- Input from tuples (for creating output structures), hash or json (for input ingestion)
- Union types are allowed
- Nested schemas definition
- Factory & Inheritance
- Generic schema

By design:

Schemas are read-only.
Rendering an invalid schema always raises an exception.
Extra fields which are not defined in the schema are simply ignored.
They can be accessed through `raw_fields` property.

Performance wasn't a big deal when creating this library. Don't expect it
to be as fast as `JSON::Serializable`, the focus is on developer experience.

## Usage

### Simple usage

```ruby
require "tarot/schema"

class MySchema < Tarot::Schema
  field content : String
end

schema = MySchema.new(content: 0)
schema.valid? # false
schema.errors # { "content": ["invalid_type"] }

schema = MySchema.new(content: "content")
schema.valid?  # true
schema.content # content
schema.to_json # {"content":"content"}

# Initialize from JSON
schema = MySchema.from(JSON.parse(%("content": "hello")))
schema.valid?  # true

schema = MySchema.new()
schema.valid? # false
schema.errors # { "content": ["required_field_not_found"] }
```

### Custom rules

```ruby
require "tarot/schema"

class MySchema < Tarot::Schema
  field age : Int64 # By default, json output in 64 bits. See converter for additional usage.

  rule age, "must_be_18" do
    age >= 18
  end
end

schema = MySchema.new(age: 19)
schema.valid? # true

schema = MySchema.new(age: 17)
schema.valid? # false
schema.errors # {"age": ["must_be_18"]}
```

### Creating and reusing a custom rule.

See docs for the list of the existing rules.

To create a rule:

```ruby
# A reusable rule
module MyEmailRule
  macro check(field, message="must_be_email")
    rule {{field}}, message do
      {{field}} =~ /[^@]+@[^@]+/
    end
  end
end

class MySchema < Tarot::Schema
  field email : String

  MyEmailRule.check "email"
end
```

Rules are connected to a specific field (above `email`) to link the error
to the good field.

Tarot's schema uses the special field `_root` for a failure occurring directly to
the structure.

### Union type

```ruby
require "tarot/schema"

class MySchema < Tarot::Schema
  field id : String|Int64
end

schema = MySchema.new(id: "hello")
schema.valid? # true
schema = MySchema.new(id: 17)
schema.valid? # true
```

You can mix it within a more complex environment:

```ruby
require "tarot/schema"

class AnotherSchema < Tarot::Schema
  field id : String
end

class MySchema < Tarot::Schema
  field data : Hash(String, Int64|String|AnotherSchema)
end

schema = MySchema.new(data: { content: "something", value: 12, even_sub_schema: {id: "Oh yeah !"} })
schema.valid? # true

schema.data["even_sub_schema"].as(AnotherSchema).id # Oh yeah !

schema = MySchema.new(data: { content: "yeah", bool: false })
schema.valid? # false, because boolean is not authorized !
```

In the example above, `{id: "yeah"}` will automatically be inferred to `AnotherSchema`.

Note: If a Union has multiple Schema whose definition overlays each other, the
first Schema found in Union will be instantiated.

### Nested schema definition

```ruby
class EventSchema < Tarot::Schema
  field id : String
  schema data do
    field source : String

    # use JSON::Any for "wildcard" the field, which then can be anything.
    # use `?` for optional presence of the field.
    field metadata : JSON::Any?
  end
end

schema = EventSchema.new(id: "1234", data: {source: "somewhere", metadata: { anything: {really: true} }})
schema.valid? # true
```

if a subschema fails, the key responsible for failure is flattened in the error:

```ruby
schema = EventSchema.new(id: "1234", data: {metadata: { anything: {really: true} }})
schema.valid? # false
schema.errors # {"data.source" => ["required_field_not_found"]}
```

You can use `optional: true` to say that the subschema is optional:

```ruby
class EventSchema < Tarot::Schema
  field id : String
  schema data, optional: true do
    field source : String
  end
end

schema = EventSchema.new(id: "test")
schema.valid? # true, because data field is optional
schema.data # EventSchema::DataNestedSchema | Nil
```

### Inheritance

Straight forward:

```ruby
class MySchema < Tarot::Schema
  field content : String
end

class InheritedSchema < MySchema
  field data : JSON::Any
end

schema = InheritedSchema.new(content: "Lorem", data: "Ipsum")
schema.valid? # true
schema.content # "Lorem"
```

### Factory

In case you want to use abstract schema and different children and instantiate
on the fly, please use the factory keyword:

```ruby
abstract class RecordSchema < Tarot::Schema
  field id : Int64
  field type : String

  factory type, {
    "users" => UserSchema,
    "teams" => TeamSchema
  }
end

class UserSchema < RecordSchema
  field first_name  : String
  field last_name   : String
end

class TeamSchema < RecordSchema
  field name        : String
end

user = RecordSchema.from(
  type: "users",
  id: 123_i64,
  first_name: "David",
  last_name: "Goodenough"
)

user.valid? # true
user.class # UserSchema
```

If the type is not found, this will throw a `Tarot::Schema::SchemaInvalidError`

In case the `type` segregator is on another level in your schema, use the hint
feature:

```ruby
abstract class RecordSchema < Tarot::Schema
  # use special _hint_ keyword to delegate the type detection to
  # the parent above. Meaning you assume this schema must be nested into a parent.
  factory _hint_, {
    "users" => UserSchema,
    "teams" => TeamSchema
  }
end

class UserSchema < RecordSchema
  field first_name  : String
  field last_name   : String
end

class TeamSchema < RecordSchema
  field name        : String
end

class RecordWrapperSchema < Tarot::Schema
  field id : Int64
  field type : String

  # use the `type` field as hint to generate the record:
  field record : RecordSchema, hint: "type" # any record
end

schema = RecordWrapperSchema.new({id: 123, type: "teams", record: { name: "A wonderful team" }})
schema.valid? # true
schema.record # TeamSchema
schema.record.as(TeamSchema).name # A wonderful team
```

### Generic

Straight-forward example:

```ruby
class Point(T) < Tarot::Schema
  field x : T
  field y : T
end

schema = Point(String).new(x: "123", y: "456")
schema.valid? # true
```

### Converter

Converter convert from JSON to a specific crystal object.
They however do not convert the other way around:

```ruby
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

class PointSchema < Tarot::Schema
  field point : Point, converter : Point::Converter
end
```

Here is a more complex conversion example:

```ruby
class ArrayPointSchema < Tarot::Schema
  field points : Array(Point), converter : ArrayConverter(Point::Converter)
end

schema = ArrayPointSchema.from(points: [[1,2], [3,4]])
```

This start to be a bit tricky, as you need to nest converter into each other.

I would recommend creating an ArrayPoint structure and a converter for this
structure instead of messing around with this approach.

Also, please note that conversion over Union types and complex structures might
be impossibly unreadable.

In the future, some work will be done on converters, with default converters
available for your types.

### Inheritance, Generic and factory (advanced)

Tarot's schema allows complex schema-building structures.

Example code which is a fictitious and naive JSONApi structure
ingestion can be found in `sample/complex_example.cr`

This example is interesting as it covers 99% of the features of this shard.

Just copy & paste in your project, change the `require` line to match
the library, and play around with it to understand how it works !

## Caveats

- Using Numbers that are not Float64 or Int64 requires the use of NumericConverter:

```ruby
class MySchema < Tarot::Schema
  # Use of IntXX instead of Int64 will fail with invalid_type.
  field integer : Int32, converter: NumericConverter(Int32)
end

```

Because of that, there is also the possibility your schema might fail when it shouldn't:

```ruby
class MySchema < Tarot::Schema
  field a_float : Float
end

schema = MySchema.from({x : 1})
schema.valid? # false, because x is Int64!
```

Same here, add `NumericConverter(Float)`.

I should be able to fix those issues shortly.

- For complex structures, you might face some errors which relate to macro
calls and might be hard to debug.

- I recommend that you keep your structures as simple as possible.

-  Some edges cases might not be covered; please provide me a failing example in issues so I can give a look and fix it!

## Installation

in your shards:

```
dependencies:
  tarot-schema:
    github: tarot/schema
```

```
require "tarot/schema"
```

## License

MIT. Please be happy while using it.