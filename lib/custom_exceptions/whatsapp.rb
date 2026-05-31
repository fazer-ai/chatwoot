module CustomExceptions::Whatsapp
  class InvalidTemplate < CustomExceptions::Base
    def message
      @data[:message]
    end

    def http_status
      422
    end
  end

  class TemplateSubmissionError < CustomExceptions::Base
    def message
      @data[:message]
    end

    def http_status
      422
    end
  end
end
