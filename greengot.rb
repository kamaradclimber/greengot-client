# frozen_string_literal: true

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
  APP_VERSION = Gem::Version.new('1.7.3')

  def self.load(auth_file)
    if File.exist?(auth_file)
      auth = JSON.parse(File.read(auth_file))

      %w[id_token device_id].each do |field|
        raise "Missing field #{field} in #{auth_file}" unless auth.key?(field)
      end

      client = GreenGotClient.new(id_token: auth['id_token'], device_id: auth['device_id'], auth_file: auth_file)
      client.check_minimum_version!
    else
      puts "No file at #{auth_file}, will go through the auth. ⚠ This will unregister your phone"
      client = GreenGotClient.new(id_token: nil, device_id: SecureRandom.uuid, auth_file: auth_file)
      client.check_minimum_version!
      client.interactive_signin_process
      client.save_auth
    end
    client
  end

  def save_auth
    # 🔐 At this point, we are effectly saving credentials to interact with the bank on the filesystem 💥
    File.write(@auth_file, JSON.pretty_generate(id_token: @id_token, device_id: @device_id))
  end

  # @throw if api version does not support us anymore
  def check_minimum_version!
    uri = URI.parse('https://api.green-got.com/minimumVersion')
    request = Net::HTTP::Get.new(uri)
    request['X-Mobile-Unique-Id'] = @device_id
    request['User-Agent'] = USER_AGENT

    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    case response.code.to_i
    when 200
      supported_version = Gem::Version.new(JSON.parse(response.body)['minimumVersion'])
      unless APP_VERSION >= supported_version
        raise "Our version (#{APP_VERSION}) is not supported, time to re-explore API routes"
      end

      puts 'Our version is supported by the API 👌'
    else
      raise 'Unable to fetch minimal version supported by the API'
    end
  end

  def interactive_signin_process
    print 'Enter email address: '
    email_address = $stdin.gets.strip
    signin(email_address)

    puts "You should receive an email to #{email_address} within a few seconds"
    print 'Enter confirmation code: '
    confirmation_code = $stdin.gets.strip
    print 'Enter last 4 digits of credit card: '
    last4digits = $stdin.gets.strip
    @id_token = check_login_code(email_address, confirmation_code, last4digits)
    puts 'Successfuly connected to greengot account'
  end

  def signin(email_address)
    uri = URI.parse('https://api.green-got.com/v2/signin')
    request = Net::HTTP::Post.new(uri)
    request.content_type = 'application/json'
    request['X-Mobile-Unique-Id'] = @device_id
    request['User-Agent'] = USER_AGENT
    request.body = JSON.dump(email: email_address)

    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    case response.code.to_i
    when 429
      puts 'Error while doing signin process because we issue too many requests, will sleep 60s and retry'
      6.times do
        sleep(10)
        print '.'
      end
      puts ''
      signin(email_address)
    when 200
      JSON.parse(response.body)
    else
      raise "Error in signin process, code was #{response.code}. Body: #{response.body}"
    end
  end

  def check_login_code(email_address, confirmation_code, last4digits)
    uri = URI.parse('https://api.green-got.com/v2/check-login-code')
    request = Net::HTTP::Post.new(uri)
    request.content_type = 'application/json'
    request['X-Mobile-Unique-Id'] = @device_id
    request['User-Agent'] = USER_AGENT
    request.body = JSON.dump(email: email_address, oneTimeCode: confirmation_code, panLast4Digits: last4digits)

    req_options = {
      use_ssl: uri.scheme == 'https'
    }

    response = Net::HTTP.start(uri.hostname, uri.port, req_options) do |http|
      http.request(request)
    end

    unless response.code.to_i == 200
      raise "Error in checking one time code, code was #{response.code}. Body: #{response.body}"
    end

    response_body = JSON.parse(response.body)
    raise 'Unable to find id' unless response_body.key?('idToken')

    response_body['idToken']
  end

  def auth_get(path)
    uri = URI.parse("https://api.green-got.com/#{path}")
    request = Net::HTTP::Get.new(uri)
    request.content_type = 'application/json'
    request['X-Mobile-Unique-Id'] = @device_id
    request['authorization'] = "Bearer #{@id_token}"
    request['User-Agent'] = USER_AGENT

    req_options = {
      use_ssl: uri.scheme == 'https'
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
    response = auth_get("/v2/transactions?#{query_params.map { |k, v| "#{k}=#{v}" }.join('&')}")
    return [] if response['transactions'].empty? || response['nextCursor'].nil?

    response['transactions'] + get_transactions(cursor: response['nextCursor'], startDate: response['nextStartDate'])
  end
end

client = GreenGotClient.load(File.join(ENV['HOME'], '.config/greengot/auth.json'))
client.user_info

all_transactions = client.get_transactions
warn "Found #{all_transactions.size} transactions in this history"
puts all_transactions.to_json
