module Tarot
  class Schema

    module TimeConverter
      def self.from_json(json : JSON::Any?, hint = nil, coercive = false) : Time
        v = json.try &.as_s?

        if v
          begin
            Time::Format::ISO_8601_DATE_TIME.parse(v)
          rescue Time::Format::Error
            raise InvalidConversionError.new("Bad time format")
          end
        else
          raise InvalidConversionError.new("Time request a String as input")
        end
      end
    end

    module NumericConverter(T)
      def self.from_json(json : JSON::Any?, hint = nil, coercive = false) : T
        case x = json.raw
        when Number
          return T.new(x)
        when String
          case x
          when /\A[0-9]+\z/
            return T.new x.to_i64
          when /\A[0-9]+\.[0-9]+\z/
            return T.new x.to_f64
          end
        end

        raise InvalidConversionError.new
      end
    end

    module ArrayConverter(T)
      def self.from_json(json : JSON::Any?, hint = nil, coercive = false)
        case value = json.try &.raw
        when Array
          value.map do |obj|
            T.from_json(obj, hint)
          end
        else
          raise InvalidConversionError.new
        end
      end
    end

    module HashConverter(T)
      def self.from_json(json : JSON::Any?, hint = nil, coercive = false)
        case value = json.try &.raw
        when Hash
          value.transform_values do |obj|
            T.from_json(obj, hint)
          end
        else
          raise InvalidConversionError.new
        end
      end
    end

    # UnionConverter will unfold union,
    # try to convert each elements of the union
    # and raise errors if none of the union elements are convertible to T.
    # It can be used directly to create converter which allow union. For example,
    # if you have a custom converter CustomConverter but your field is a union with
    # String, you can do:
    #
    # ```
    # field my_field : String|MySpecialType,
    #       converter: UnionConverter(
    #                     UniversalConverter(String) | MySpecialTypeConverter
    #                  )
    # ```
    # (note than to convert string you can use UniversalConverter)
    #
    module UnionConverter(T)
      def self.from_json(json : JSON::Any?, hint = nil, coercive = false) : T
        {% begin %}
          {% for type in T.union_types %}
          begin
            return UniversalConverter({{type}}).from_json(json, hint)
          rescue
            # Do nothing and try next in the union.
          end
          {% end %}

          raise InvalidConversionError.new
        {% end %}
      end
    end

    # This converter will convert any structure which can be converted
    # to T.
    #
    # Basically, it will unfold Union, generics parameters inside Hash or Array.
    # It will deals with Schema and Numeric type too.
    #
    # This module should not be used directly; it's part of the way Tarot's schema
    # works.
    module UniversalConverter(T)
      def self.from_json(json : JSON::Any?, hint = nil, coercive = false) : T
        {% if T.union? %}
          UnionConverter(T).from_json(json, hint)
        {% elsif T < ::JSON::Any %}
          json.not_nil!
        {% elsif T < Schema %}
          T.from_json(json, hint)
        {% elsif T < Number %}
          NumericConverter(T).from_json(json, hint)
        {% elsif T < Array %}
          ArrayConverter(UniversalConverter({{T.type_vars.first}})).from_json(json, hint)
        {% elsif T < Hash %}
          HashConverter(UniversalConverter({{T.type_vars[1]}})).from_json(json, hint)
        {% else %}
          return json if json.is_a?(T)

          value = json.try &.raw
          if value.is_a?(T)
            return value.as(T)
          else
            raise InvalidConversionError.new
          end
        {% end %}
      end
    end
  end
end
