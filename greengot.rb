require 'net/http'
require 'uri'
require 'json'
require 'securerandom'

class GreenGotClient
  def initialize(device_id:, id_token:, auth_file:)
    @device_id = device_id
    @id_token = id_token
    @auth_file = auth_file
  end
  USER_AGENT = 'github.com/kamaradclimber/greengot-client'

  def self.load(auth_file)
    if File.exist?(auth_file)
      auth = JSON.parse(File.read(auth_file))

      %w[id_token device_id].each do |field|
        raise "Missing field #{field} in #{auth_file}" unless auth.key?(field)
      end

      GreenGotClient.new(id_token: auth['id_token'], device_id: auth['device_id'], auth_file: auth_file)
    else
      puts "No file at #{auth_file}, will go through the auth. ⚠ This will unregister your phone"
      client = GreenGotClient.new(id_token: nil, device_id: SecureRandom.uuid, auth_file: auth_file)
      client.interactive_signin_process
      client.save_auth
      client
    end
  end

  def save_auth
    # 🔐 At this point, we are effectly saving credentials to interact with the bank on the filesystem 💥
    File.write(@auth_file, JSON.pretty_generate(id_token: @id_token, device_id: @device_id))
  end

  def interactive_signin_process
    print "Enter email address: "
    email_address = STDIN.gets.strip
    signin(email_address)

    puts "You should receive an email to #{email_address} within a few seconds"
    print "Enter confirmation code: "
    confirmation_code = STDIN.gets.strip
    print "Enter last 4 digits of credit card: "
    last4digits = STDIN.gets.strip
    @id_token = check_login_code
    puts "Successfuly connected to greengot account"
  end

  def signin(email_address)
    uri = URI.parse("https://api.green-got.com/v2/signin")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request["X-Mobile-Unique-Id"] = @device_id
    request["User-Agent"] = USER_AGENT
    request.body = JSON.dump(email: email_address)

    req_options = {
      use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    raise "Error in signin process, code was #{response.code}. Body: #{response.body}" unless response.code.to_i == 200
    JSON.parse(response.body)
  end

  def check_login_code(email_address, confirmation_code, last4digits)
    uri = URI.parse("https://api.green-got.com/v2/check-login-code")
    request = Net::HTTP::Post.new(uri)
    request.content_type = "application/json"
    request["X-Mobile-Unique-Id"] = @device_id
    request["User-Agent"] = USER_AGENT
    request.body = JSON.dump(email: email_address, oneTimeCode: confirmation_code, panLast4Digits: last4digits)

    req_options = {
      use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    raise "Error in checking one time code, code was #{response.code}. Body: #{response.body}" unless response.code.to_i == 200
    response_body = JSON.parse(response.body)
    raise "Unable to find id" unless response_body.key?('idToken')
    response_body['idToken']
  end

  def auth_get(path)
    uri = URI.parse("https://api.green-got.com/#{path}")
    request = Net::HTTP::Get.new(uri)
    request.content_type = "application/json"
    request["X-Mobile-Unique-Id"] = @device_id
    request["authorization"] = "Bearer #{@id_token}"
    request["User-Agent"] = USER_AGENT

    req_options = {
      use_ssl: uri.scheme == "https",
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    case response.code.to_i
    when 401
      # we should likely re-authenticate
      puts "Fetching #{path} was unauthorized by greengot API. It's likely we need to re-auth. Please delete #{@auth_file} and retry"
      raise
    when 200
      JSON.parse(response.body)
    else
      raise "Error in fetching #{uri} info, code was #{response.code}. Body: #{response.body}"
    end
  end

  def user_info
    auth_get('user')
  end

  def get_transactions(**query_params)
    # here we assume query params are correctly encoded, no verification is done
    query_params = { limit: 50 }.merge(query_params)
    response = auth_get("/v2/transactions?#{query_params.map { |k,v| "#{k}=#{v}"}.join('&')}")
    return [] if response['transactions'].empty? || response['nextCursor'].nil?

    response['transactions'] + get_transactions(cursor: response['nextCursor'], startDate: response['nextStartDate'])
  end
end

client = GreenGotClient.load(File.join(ENV['HOME'], ".config/greengot/auth.json"))
client.user_info

all_transactions = client.get_transactions
puts "Found #{all_transactions.size} transactions in this history"
require 'pry'
binding.pry
