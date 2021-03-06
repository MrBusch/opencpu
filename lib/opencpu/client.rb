module OpenCPU
  class Client
    include HTTMultiParty

    def initialize
      self.class.base_uri OpenCPU.configuration.endpoint_url
      self.class.default_timeout(OpenCPU.configuration.timeout) unless OpenCPU.configuration.timeout.nil?
    end

    def execute(package, function, options = {})
      user   = options.fetch :user, :system
      data   = options.fetch :data, {}
      format = options.fetch :format, :json
      process_query package_url(package, function, user, :json), data, format do |response|
        JSON.parse(response.body)
      end
    end

    def prepare(package, function, options = {})
      user = options.fetch :user, :system
      data = options.fetch :data, {}
      format = options.fetch :format, :json
      process_query package_url(package, function, user), data, format do |response|
        location  = response.headers['location']
        resources = response.body.split(/\n/)
        OpenCPU::DelayedCalculation.new(location, resources)
      end
    end

    private

    def process_query(url, data, format, &block)
      return fake_response_for(url) if OpenCPU.test_mode?

      response  = self.class.post(url, request_options(data, format))

      case response.code
      when 200..201
        return yield(response)
      when 400
        fail '400: Bad Request\n' + response.body
      else
        fail "#{response.code}:\n #{response.body}"
      end
    end

    def request_options(data, format)
      options = {
        verify: OpenCPU.configuration.verify_ssl
      }

      case format
      when :json
        options[:body] = data.to_json
        options[:headers] =  {"Content-Type" => 'application/json'}
      when :urlencoded
        options[:query] = data
      end

      if OpenCPU.configuration.username && OpenCPU.configuration.password
        options[:basic_auth] = {
          username: OpenCPU.configuration.username, password: OpenCPU.configuration.password
        }
      end
      options
    end

    def package_url(package, function, user = :system, format = nil)
      return ['', 'library', package, 'R', function, format.to_s].join('/') if user == :system
      return ['', 'user', user, 'library', package, 'R', function, format.to_s].join('/')
    end

    def fake_response_for(url)
      key = derive_key_from_url(url)
      OpenCPU.configuration.fake_responses.delete key
    end

    def derive_key_from_url(url)
      url_parts    = url.gsub!(/^\//, '').split('/')
      remove_items = ['R', 'library', 'json']
      (url_parts - remove_items).join('/')
    end
  end
end
