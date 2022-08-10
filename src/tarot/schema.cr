require "json"

require "./schema/converters"
require "./schema/validators"
require "./schema/errors"

module Tarot
  class Schema
    getter  raw_fields : JSON::Any
    getter! errors : Hash(String, Array(String))?

    KEYS = {} of Nil => Nil
    RULES = [] of Nil

    macro inherited
      {% begin %}
        {%
          type = @type.ancestors.first
          keys = type.constants.select{ |x| x == "KEYS".id }.first
          rules = type.constants.select{ |x| x == "RULES".id }.first
        %}

        # copy the keys from parent. This is definitely too complex
        # but necessary to allow schema inheritance.
        # Find another method would be great
        {% if keys %}
          \{% begin %}
            \{% if {{type}}::{{keys}}.size == 0 %}
            KEYS = {} of Nil => Nil
            \{% else %}
            KEYS = { \{% for k, v in {{type}}::{{keys}} %} \{{k}}: \{{v}}, \{% end %} }
            \{% end %}
          \{% end %}
        {% end %}

        {% if rules %}
          \{% begin %}
            \{% if {{type}}::{{rules}}.size == 0 %}
            RULES = [] of Nil
            \{% else %}
            RULES = [ \{% for rule in {{type}}::{{rules}} %} \{{rule}}, \{% end %} ]
            \{% end %}
          \{% end %}
        {% end %}

        macro finished
          _build_validate
          _build_to_json
        end
      {% end %}
    end

    macro field(name_and_type, converter = nil, key = nil, hint = nil)
      {%
        name = name_and_type.var

        if name.id.stringify == "errors" || name.id.stringify == "raw_fields"
          raise "`errors` and `raw_fields` are reserved keywords.\n"+
                "Please `key` parameter to map correctly.\n"+
                "Example: field another_name, key: \"#{name.id}\""
        end

        type = name_and_type.type
        converter ||= "UniversalConverter(#{type})".id
      %}

      {%
        KEYS[name] = {
          type: type,
          converter: converter,
          key: key || name.stringify,
          hint: hint
        }
      %}

      @__converted_{{name}} : Union({{type}}, Nil)

      def {{name}} : {{type}}
        @__converted_{{name}}.as({{type}})
      end
    end

    macro rule(field, message, &block)
      {%
        RULES << {
          field: field.id.stringify,
          message: message,
          body: block.body.stringify
        }
      %}
    end

    macro schema(name, optional = false)
      {% class_name = "#{name.id.stringify.camelcase.id}NestedSchema".id %}

      class {{class_name}} < Tarot::Schema
        {{yield}}
      end

      field {{name.id}} : {{class_name}}{{(optional ? "?" : "").id}},
          converter: {{class_name}}
    end

    # Generate a factory for inherited schema, which bind the value of the
    # field `on` to a specific subclass defined by the tuple:
    #
    # ```
    #   Event.factory("type", {"google": GoogleEvent, "facebook" : FacebookEvent})
    # ```
    # Therefore, when using `Event.from(json)`,
    # this will create GoogleEvent or FacebookEvent.
    macro factory(on, map, fallback = false)
      def self.from(value : JSON::Any, hint = nil)
        puts "From #{value.inspect} => #{hint}"
        if hash = value.as_h?
          {% if on == "_hint_" %}
            selector = hint
          {% else %}
            selector = hash[{{on.id.stringify}}]?
          {% end %}

          {% begin %}
          case selector
          {% for key, value in map %}
          when {{key}}
            if self == {{value}}
              {{value}}.make_new(value) # avoid infinite recursion
            else
              {{value}}.from(value, hint)
            end
          {% end %}
          else
            {% if fallback %}
              new(value) # fallback on parent
            {% else %}
              raise InvalidConversionError.new("unknown factory for: #{hash[{{on.id.stringify}}]?.inspect}")
            {% end %}
          end
          {% end %}
        else
          raise InvalidConversionError.new("not an hash")
        end
      end
    end

    def validate_nested(root : String, value)
      case value
      when Tarot::Schema
        unless value.valid?
          value.errors.each do |key, errors|
            errors.each do |error|
              add_error( {root, key }.join("."), error)
            end
          end
        end
      when Array
        value.each_with_index do |elm, idx|
          validate_nested({root, idx}.join, elm)
        end
      when Hash
        value.each do |key, value|
          validate_nested({root, key}.join, value)
        end
      end
    end

    macro _build_validate
      def validate
        @errors = {} of String => Array(String)

        if !@raw_fields.as_h?
          add_error("_root", "must_be_a_hash")
          return false
        end

        {% begin %}
          {% for k, v in KEYS %}
            {%
              key = v[:key].id.stringify
              converter = v[:converter]
              type = v[:type]
              hint = v[:hint]
            %}

            value = @raw_fields[{{key}}]?

            if value.nil? && !nil.is_a?({{type}})
              add_error({{key}}, "required_field_not_found")
            elsif value
              begin
                {% if hint %}
                hint = @raw_fields[{{hint}}]?.try &.raw
                {% else %}
                hint = nil
                {% end %}
                @__converted_{{k}} = value = {{converter}}.from(value, hint)
                validate_nested({{key}}, value )
              rescue InvalidConversionError
                add_error({{key}}, "invalid_type")
              end
            end
          {% end %}

          delayed_errors = [] of {String, String}

          {% for value in RULES %}
            if field_valid?({{value[:field]}})
              valid = -> do
                {{value[:body].id}}
              end.call

              unless valid
                delayed_errors << { {{value[:field]}}, {{value[:message]}} }
              end
            end
          {% end %}

          delayed_errors.each do |err|
            add_error(err[0], err[1])
          end
        {% end %}

        return valid?
      end
    end

    macro _build_to_json
      def to_json(json : JSON::Builder)
        raise SchemaInvalidError.new("the schema is invalid") unless valid?
        {% begin %}
          json.object do
            {% for k, v in KEYS %}
              json.field {{v[:key]}} do
                {{k.id}}.to_json(json)
              end
            {% end %}
          end
        {% end %}
      end
    end

    def initialize(@raw_fields : JSON::Any)
    end

    def valid?
      validate if @errors.nil?
      errors.empty?
    end

    def valid!
      return true if valid?
      raise SchemaInvalidError.new
    end

    def field_valid?(field)
      !errors.has_key?(field)
    end

    def add_error(key : String, error : String)
      errors = (@errors.not_nil![key] ||= [] of String)
      errors << error
    end

    def self.new(**tuple)
      new(tuple_to_json_any(**tuple))
    end

    def self.new(parser : JSON::PullParser)
      new(JSON::Any.new(parser))
    end

    def self.from(**tuple)
      from(tuple_to_json_any(**tuple))
    end

    # :nodoc:
    # this method is used internally to trick the compiler
    # which would otherwise complain that we *could* try to instantiate
    # an abstract schema.
    #
    # By defining this we prevent the compiler to complain, and can use
    # the factories the way they were designed.
    #
    # This should not be used in any time from code outside of here.
    def self.make_new(value : JSON::Any)
      {% if @type.abstract? %}
        raise "Type {{@type}} cannot be instantiated because it's abstract"
      {% else %}
        new(value)
      {% end %}
    end

    def self.from(value : JSON::Any, hint = nil)
      if hash = value.as_h?
        {% unless @type.abstract? %}
          new(value)
        {% else %}
          raise "The schema type {{@type}} is abstract. You must setup a factory"
        {% end %}
      else
        raise InvalidConversionError.new("not and hash")
      end
    end
  end
end

def tuple_to_json_any(**tuple) : JSON::Any
  output = {} of String => JSON::Any
  tuple.each do |k, v|
    output[k.to_s] = \
      case v
      when NamedTuple
        tuple_to_json_any(**v)
      when Float
        JSON::Any.new(v.to_f64)
      when Number
        JSON::Any.new(v.to_i64)
      when Array
        JSON::Any.new(v.map{ |x|
          if x.is_a?(NamedTuple)
            tuple_to_json_any(**x)
          else
            JSON::Any.new(x)
          end
        })
      when Hash
        JSON::Any.new(v.transform_values{ |x| JSON::Any.new(x) })
      else
        JSON::Any.new(v)
      end
  end

  JSON::Any.new(output)
end
