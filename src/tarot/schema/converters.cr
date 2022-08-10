module Tarot
  class Schema

    module TimestampConverter
      def self.from(json : JSON::Any?, hint = nil) : Time
        if (v = json.try &.as_f?) || (v = json.try &.as_i64?)
          Time.unix_ms((v * 1000).to_i64)
        else
          raise InvalidConversionError.new
        end
      end
    end

    module NumericConverter(T)
      def self.from(json : JSON::Any?, hint = nil) : T
        case json.raw
        when Number
          T.new(json.raw.as(Number))
        else
          raise InvalidConversionError.new
        end
      end
    end

    module ArrayConverter(T)
      def self.from(json : JSON::Any?, hint = nil) : Array(T)
        case value = json.try &.raw
        when Array
          value.map do |obj|
            UniversalConverter(T).from(obj, hint)
          end
        else
          raise InvalidConversionError.new
        end
      end
    end

    module HashConverter(T)
      def self.from(json : JSON::Any?, hint = nil) : Hash(String, T)
        case value = json.try &.raw
        when Hash
          value.transform_values do |obj|
            UniversalConverter(T).from(obj, hint)
          end
        else
          raise InvalidConversionError.new
        end
      end
    end

    module UnionConverter(T)
      def self.from(json : JSON::Any?, hint = nil) : T
        {% begin %}
          {% for type in T.union_types %}
          begin
            return UniversalConverter({{type}}).from(json, hint)
          rescue
            # Do nothing and try next in the union.
          end
          {% end %}

          raise InvalidConversionError.new
        {% end %}
      end
    end

    module UniversalConverter(T)
      def self.from(json : JSON::Any?, hint = nil) : T
        {% if T.union? %}
          UnionConverter(T).from(json, hint)
        {% elsif T < ::JSON::Any %}
          json.not_nil!
        {% elsif T < Schema %}
          T.from(json, hint)
        {% elsif T < Array %}
          ArrayConverter({{T.type_vars.first}}).from(json, hint)
        {% elsif T < Hash %}
          HashConverter({{T.type_vars[1]}}).from(json, hint)
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
