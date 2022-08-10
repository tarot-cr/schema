# Tarot Schema Validation

Schema validation for JSON structure in Crystal. Part of the Tarot project.

Wild features, like:

- Type and presence validation + custom rules
- Input from tuples (for creating output) or json (for creating input)
- Union types allowed
- Nested schemas definition
- Factory & Inheritance
- Generic schema

By design:

Schemas are read-only.
Rendering an invalid schema always raises an exception.
Extra fields which are not defined in the schema are simply ignored.
They can be accessed through `raw_fields` property.

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

### Existing rules

See docs for the list of the existing rules.

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
```

### Inheritance, Generic and factory (advanced)

Tarot's schema allows complex schema-building structures.

Example code which is a fictitious and naive JSONApi structure
ingestion can be found in `sample/complex_example.cr`

Just copy & paste in your project, change the `require` line to match
the library, and play around with it.

## Caveats

For complex structures, you might face some errors which relate to macro
calls and might be hard to debug.

I recommend that you keep your structures as simple as possible.

Some edges cases might not be covered; please provide me a failing example in PR so I can give a look and fix it!

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