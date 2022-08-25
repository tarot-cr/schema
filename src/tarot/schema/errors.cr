module Tarot
  class Schema
    class InvalidConversionError < Exception
    end

    class SchemaInvalidError < Exception
      getter schema : Tarot::Schema

      def initialize(@schema)
      end
    end
  end
end
