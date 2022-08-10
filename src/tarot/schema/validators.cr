module Tarot
  class Schema

    module Validate
      macro email(field, message = "must_be_email")
        rule {{field}}, {{message}} do
          value = self.{{field.id}}
          if value.is_a?(String)
            self.{{field.id}} =~ /^\w+([\.-]?\w+)*@\w+([\.-]?\w+)*(\.\w{2,3})+$/
          else
            next true
          end
        end
      end
    end


  end
end