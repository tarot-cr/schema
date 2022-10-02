require "../../src/tarot/schema"
require "spec"

module SchemaSpec
  class SimpleSchema < Tarot::Schema
    field name : String
    field numeric : Int64
  end

  class UnionSchema < Tarot::Schema
    field nilable : Bool?, emit_null: true
    field complex_union : Array(String) | Hash(String, String)
  end

  class NumberSchema < Tarot::Schema
    field number : Float32
  end

  class CustomFieldSchema < Tarot::Schema
    field custom : JSON::Any
  end

  class RuleSchema < Tarot::Schema
    field age : Int32, converter: NumericConverter(Int32)

    rule age, "must be at least 18 years old" do
      self.age >= 18
    end
  end

  class DefaultSchema < Tarot::Schema
    field age : Int32 = 18
  end

  class SchemaWithHash < Tarot::Schema
    field hash : Hash(String, JSON::Any)
  end

  class ValidatorSchema < Tarot::Schema
    field email : String?

    Validate.email "email", "should be email"
  end

  # Inheritance stuff
  class EventSchema < Tarot::Schema
    field type : String
    field time : String # random stuff should got inherited

    factory "type", {
      "Google" => GoogleEventSchema,
      "Facebook" => FacebookEventSchema,
      "FacebookAd" => FacebookAdEventSchema
    }
  end

  class GoogleEventSchema < EventSchema
    field google_key : String
  end

  class FacebookEventSchema < EventSchema
    schema data do
      field fb_data : String
    end

    factory "subtype", {
      "Ad" => FacebookAdEventSchema
    }
  end

  # Double inheritance
  class FacebookAdEventSchema < FacebookEventSchema
    field ad_number : Int64
  end

  class NestedSchema < Tarot::Schema
    field parent : String

    schema nested do
      field content : String

      schema nested2 do
        field content2 : String
      end
    end
  end

  class ComplexSchema < Tarot::Schema
    class Event < Tarot::Schema
      field metadata : JSON::Any? # anything, really.
      field name : String
    end

    field timestamp : Time, converter: TimeConverter
    field events : Array(Event | String)?
  end

  class GenericSchema(T) < Tarot::Schema
    field metadata : String
    field data : T
  end

  describe "Schema" do
    context "basic" do
      it "parses simple schema" do
        schema = SimpleSchema.new(name: "Test", numeric: 1)
        schema.valid?.should eq(true)
        schema.name.should eq("Test")
        schema.numeric.should eq(1)
      end

      it "detects invalid schema" do
        schema = SimpleSchema.new(name: "Test", numeric: "String")
        schema.valid?.should eq(false)

        schema.field_valid?("name").should eq(true)
        schema.field_valid?("numeric").should eq(false)

        key, value = schema.errors.first
        key.should eq("numeric")
        value.should eq(["invalid_type"])
      end

      it "valid! raises error" do
        schema = SimpleSchema.new(name: "Test", numeric: "String")

        expect_raises(Tarot::Schema::SchemaInvalidError) do
          schema.valid!
        end
      end

      it "coerces data" do
        schema = SimpleSchema.new(name: "Test", numeric: "1")
        schema.valid?.should eq(true)
      end

      it "loads from_json json" do
        schema = SimpleSchema.from_json(%({"name": "Test", "numeric": 0}))
        schema.valid?.should eq(true)
      end
    end

    context "custom" do
      it "allows custom content to the structure" do
        custom = CustomFieldSchema.new(custom: {a: {b: true}})
        custom.valid?
        custom.valid?.should eq(true)
      end

      it "allow use of to tuple" do
        custom = CustomFieldSchema.new(custom: {a: {b: true}})
        custom.to_tuple.class.should eq(NamedTuple(custom: JSON::Any))
      end
    end

    context "number casting" do
      it "works with casting numbers" do
        n = NumberSchema.new(number: 1)
        n.valid?.should eq(true)
      end
    end

    context "default schema" do
      it "allows default fields" do
        schema = DefaultSchema.new
        schema.valid?.should eq(true)
      end
    end

    context "schema with hash" do
      it "allow schema with hash" do
        schema = SchemaWithHash.new(hash: { x: 1 })
        schema.valid?.should eq(true)
      end
    end

    context "unions" do
      it "validates union fields" do
        schema = UnionSchema.new(complex_union: ["1", "2", "3"])
        schema.valid?.should eq(true)
        schema.to_json.should eq(%({"nilable":null,"complex_union":["1","2","3"]}))
      end

      it "detects errors in unions" do
        schema = UnionSchema.new(complex_union: ["1", 1_i64, "3"])
        schema.valid?.should eq(false)
        key, value = schema.errors.first
        key.should eq("complex_union")
        value.should eq(["invalid_type"])
      end
    end

    context "rules" do
      it "validates rules" do
        schema = RuleSchema.new(age: 17)
        schema.valid?.should eq(false)
        key, value = schema.errors.first
        key.should eq("age")
        value.should eq(["must be at least 18 years old"])

        schema = RuleSchema.new(age: 18)
        schema.valid?.should eq(true)
      end

      it "doesn't check if presence is missing and/or type is invalid" do
        schema = RuleSchema.new
        schema.valid?.should eq(false)
        key, value = schema.errors.first
        key.should eq("age")
        value.should eq(["required_field_not_found"])
      end
    end

    context "inherited schema + factory" do
      it "works" do
        schema = EventSchema.from_json(
          type: "Google",
          time: "now",
          google_key: "1234"
        )
        schema.class.should eq(GoogleEventSchema)
        schema.valid?.should eq(true)
      end

      it "nests factories with subtypes" do
        schema = EventSchema.from_json(
          type: "Facebook",
          subtype: "Ad",
          time: "yesterday",
          data: {
            fb_data: "yes"
          },
          ad_number: 1234
        )
        schema.class.should eq(FacebookAdEventSchema)
        schema.valid?.should eq(true)
        schema.to_json.should eq(%({"type":"Facebook","time":"yesterday","data":{"fb_data":"yes"},"ad_number":1234}))
      end

      it "throw errors if factory not found" do
        expect_raises Tarot::Schema::InvalidConversionError do
          schema = EventSchema.from_json(
            type: "unknown",
          )
        end
      end

    end

    context "nested schema" do
      it "detects errors in nested schema" do
        schema = NestedSchema.new(parent: "ok", nested: { content: "ok", nested2: { content2: 1_i64 } })

        schema.valid?.should eq(false)
        key, value = schema.errors.first

        key.should eq("nested.nested2.content2")
        value.should eq(["invalid_type"])
      end
    end

    context "generic" do
      it "can use generic to build stuff" do
        generic = GenericSchema(SimpleSchema).new(
          data: { name: "hello", numeric: 1_i64 },
          metadata: "data"
        )
        generic.valid?
        generic.valid?.should eq(true)
        generic.to_json.should eq(%({"metadata":"data","data":{"name":"hello","numeric":1}}))
      end

      it "still detects errors" do
        generic = GenericSchema(SimpleSchema).new(
          data: { name: "hello" },
          metadata: "data"
        )
        generic.valid?

        generic.valid?.should eq(false)
        key, value = generic.errors.first

        key.should eq("data.numeric")
        value.should eq(["required_field_not_found"])

        generic.data.name.should eq("hello")

        expect_raises(TypeCastError) do
          generic.data.numeric
        end
      end
    end

    context "complex schema" do
      it "can parse this complex json" do
        json = <<-JSON
          [{
            "timestamp": "2022-08-09T17:22:38Z",
            "events": []
          },
          {
            "timestamp": "2022-08-09T17:22:40Z"
          },
          {
            "timestamp": "2022-08-09T17:22:42Z",
            "events": ["happened", {"name": "created", "metadata": {"some": "cool_stuff"}}]
          }]
        JSON

        arr = JSON.parse(json).as_a

        schemas = arr.map do |item|
          s = ComplexSchema.new(item)
          s.valid?.should eq(true)
          s
        end

        output = JSON.parse(schemas.to_json)

        # ensure all is the same.
        output.should eq(arr)
      end
    end

  end
end