# Tarot Schema Validation

Schema validation for JSON structure in Crystal. Part of the Tarot project.

The idea is to simplify tremendously data consumption and output, in a JSON-centric
environment, like an API server for example.

After working with Crystal for more than 2 years, I always found data
management a bit difficult and a long process.

Crystal standard library offers very great tools like JSON::Serializable but
they are focused on performance and not well-suited to dynamic input ingestion,
like a web server.

Hence I've built Tarot's Schema, the fastest way to describe input and output
coming from JSON or JSON-like (HTTP  parameters), validate them and consume
them.

Features are pretty wild and include:

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
Although they can be accessed through `raw_fields` property.

Performance wasn't a big concern when creating this library. Don't expect it
to be as fast as `JSON::Serializable`, the focus is on developer experience.

Secure input/output and ship your features quickly!

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

Optional fields for `field` helper are:
- `key` by default the name of the attribute equates to the name of the key in JSON schema. Use this to map the keys differently. Note that `errors` and `raw_fields` are
protected terms and will require the use of another term for the field name.
- `emit_null` by default `Schema#to_json` won't emit the `null` fields. Use `emit_null` to ensure the data is outputted correctly even if null.
- `hint` Used by nested schema factory. See #factory to learn more about it.
- `converter` Use a special converter for _non-schema_ complex structures. See the converter section below.

### Rules

Rules are used to validate the content.

By default, presence and type validation are handled by describing your field; additional constraints can be added via rules.

Rules are blocks of code returning a boolean, which decide whether your schema is valid or not.

You simply set up the rule, and target a specific field (which will be used to display the error message) and the error message related to the failure of this rule.

Note that if the field related to the rule is not valid, the rule will not be checked during validation.

Here is a simple example:


```ruby
require "tarot/schema"

class MySchema < Tarot::Schema
  field current_age : Int64, key: "currentAge" # camelcase from the json source.

  rule age, "must_be_18" do
    age >= 18
  end
end

schema = MySchema.new(currentAge: 19)
schema.valid? # true

schema = MySchema.new(currentAge: 17)
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


#### Abstract class

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

#### Hint feature

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

#### Fallback

In case your object is not abstract, you can fallback to
the main object using `fallback` keyword:

```ruby
class RecordSchema < Tarot::Schema
  field id : Int64
  field type : String

  # assuming this is a Schema, for the children.
  field attributes : Tarot::Schema

  factory type, {
    "users" => UserSchema,
    "teams" => TeamSchema
  }, fallback: true
end

class UserSchema < RecordSchema
  # redefine attributes field
  schema attributes do
    field first_name  : String
    field last_name   : String
  end
end

class TeamSchema < RecordSchema
  # redefine attributes field
  schema attributes do
    field name        : String
  end
end

schema = RecordSchema.from(
  id: 123,
  type: "custom", # no factory for this type.
  attributes: { some_attributes: true }
)
schema.valid? # true
schema.class # RecordSchema, it fallback to the main class because factory is not found
schema.attributes # Tarot::Schema. Nothing accessible as-is
schema.attributes["some_attributes"].as_bool # true
```

### Generic

Generic are working with Tarot's schema:

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

I would recommend creating an `ArrayPoint` structure and a converter for this
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
the library, and play around with it to understand how it works!

## Caveats

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