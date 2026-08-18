require "base64"
require "json"
require "rack/session/cookie"
require "securerandom"
require "sinatra/base"
require "uri"
require "webauthn"

require_relative "lib/passkey_store"

class PasskeyTestApp < Sinatra::Base
  class ApiError < StandardError
    attr_reader :status_code

    def initialize(message, status_code = 422)
      super(message)
      @status_code = status_code
    end
  end

  DEFAULT_ORIGIN = "http://localhost:3000".freeze
  WEBAUTHN_ORIGIN = ENV.fetch("WEBAUTHN_ORIGIN", DEFAULT_ORIGIN).delete_suffix("/")
  WEBAUTHN_RP_ID = ENV.fetch("WEBAUTHN_RP_ID", URI(WEBAUTHN_ORIGIN).host)
  PRODUCTION_COOKIE = WEBAUTHN_ORIGIN.start_with?("https://")

  WebAuthn.configure do |config|
    config.allowed_origins = [WEBAUTHN_ORIGIN]
    config.rp_id = WEBAUTHN_RP_ID
    config.rp_name = "Passkey Test Lab"
    config.encoding = :base64url
  end

  configure do
    set :root, __dir__
    set :public_folder, File.join(__dir__, "public")
    set :views, File.join(__dir__, "views")
    set :show_exceptions, false
    set :raise_errors, false
    set :dump_errors, true
    set :store, PasskeyStore.new(ENV.fetch("PASSKEY_STORE_PATH", File.join(__dir__, "data", "passkeys.json")))
  end

  session_secret = ENV.fetch("SESSION_SECRET") do
    "development-only-session-secret-#{'x' * 64}"
  end

  use Rack::Session::Cookie,
      key: "passkey_test_session",
      secret: session_secret,
      same_site: :lax,
      secure: PRODUCTION_COOKIE,
      httponly: true,
      expire_after: 86_400

  helpers do
    def json_body
      request.body.rewind
      body = request.body.read
      raise ApiError.new("JSON リクエストが空です", 400) if body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      raise ApiError.new("JSON の形式が正しくありません", 400)
    end

    def json_response(payload, status_code = 200)
      content_type :json
      status status_code
      JSON.generate(payload)
    end

    def normalize_username(value)
      value.to_s.strip.downcase
    end

    def validated_username(value)
      username = value.to_s.strip
      if username.length < 2 || username.length > 64 || username.match?(/[[:cntrl:]]/)
        raise ApiError.new("ユーザー名は2〜64文字で入力してください")
      end
      username
    end

    def current_user_key
      session[:user_key]
    end

    def current_user
      return nil unless current_user_key

      settings.store.find_user(current_user_key)
    end

    def logged_in?
      !current_user.nil?
    end

    def require_login!
      redirect "/" unless logged_in?
    end

    def clear_registration_challenge!
      session.delete(:registration_challenge)
      session.delete(:registration_user_key)
    end

    def clear_authentication_challenge!
      session.delete(:authentication_challenge)
      session.delete(:authentication_user_key)
    end

    def user_handle_matches?(returned_handle, stored_handle)
      return true if returned_handle.nil? || returned_handle.to_s.empty?

      expected_bytes = decode_base64url(stored_handle)
      returned = returned_handle.to_s
      returned.b == expected_bytes.b || returned == stored_handle
    end

    def decode_base64url(value)
      string = value.to_s
      padding = "=" * ((4 - string.length % 4) % 4)
      Base64.urlsafe_decode64(string + padding)
    end
  end

  before do
    headers "Cache-Control" => "no-store", "X-Content-Type-Options" => "nosniff"
  end

  before %r{/api/.*} do
    unless request.media_type == "application/json"
      raise ApiError.new("Content-Type は application/json を指定してください", 415)
    end
  end

  get "/health" do
    content_type :json
    JSON.generate(status: "ok")
  end

  get "/" do
    redirect "/account" if logged_in?
    erb :index
  end

  get "/account" do
    require_login!
    erb :account
  end

  post "/logout" do
    session.clear
    redirect "/?logged_out=1", 303
  end

  post "/api/register/options" do
    payload = json_body
    username = validated_username(payload["username"])
    user_key = normalize_username(username)
    existing_user = settings.store.find_user(username)

    if existing_user && existing_user.fetch("credentials", []).any? && current_user_key != user_key
      raise ApiError.new("このユーザー名にはすでにパスキーが登録されています", 409)
    end

    user = settings.store.ensure_user(username, handle: WebAuthn.generate_user_id)
    options = WebAuthn::Credential.options_for_create(
      user: {
        id: user.fetch("handle"),
        name: user.fetch("name"),
        display_name: user.fetch("name")
      },
      exclude: user.fetch("credentials", []).map { |credential| credential.fetch("id") },
      authenticator_selection: {
        resident_key: "required",
        user_verification: "required"
      },
      attestation: "none"
    )

    session[:registration_challenge] = options.challenge
    session[:registration_user_key] = user_key
    json_response(publicKey: options.as_json)
  end

  post "/api/register/verify" do
    payload = json_body
    challenge = session[:registration_challenge]
    user_key = session[:registration_user_key]
    raise ApiError.new("登録チャレンジの有効期限が切れました。もう一度お試しください", 400) unless challenge && user_key

    webauthn_credential = WebAuthn::Credential.from_create(payload.fetch("credential"))
    webauthn_credential.verify(challenge, user_verification: true)

    transports = payload.dig("credential", "response", "transports")
    settings.store.add_credential(
      user_key,
      id: webauthn_credential.id,
      public_key: webauthn_credential.public_key,
      sign_count: webauthn_credential.sign_count,
      transports: transports
    )

    clear_registration_challenge!
    session[:user_key] = user_key
    json_response(ok: true, redirect: "/account")
  rescue KeyError
    raise ApiError.new("登録レスポンスが不足しています", 400)
  rescue ArgumentError => e
    raise ApiError.new(e.message, 409)
  end

  post "/api/login/options" do
    payload = json_body
    requested_username = payload["username"].to_s.strip
    options_arguments = { user_verification: "required" }

    if requested_username.empty?
      session.delete(:authentication_user_key)
    else
      user = settings.store.find_user(requested_username)
      unless user && user.fetch("credentials", []).any?
        raise ApiError.new("登録済みのパスキーが見つかりません", 404)
      end

      session[:authentication_user_key] = normalize_username(requested_username)
      options_arguments[:allow] = user.fetch("credentials").map { |credential| credential.fetch("id") }
    end

    options = WebAuthn::Credential.options_for_get(**options_arguments)
    session[:authentication_challenge] = options.challenge
    json_response(publicKey: options.as_json)
  end

  post "/api/login/verify" do
    payload = json_body
    challenge = session[:authentication_challenge]
    raise ApiError.new("ログインチャレンジの有効期限が切れました。もう一度お試しください", 400) unless challenge

    webauthn_credential = WebAuthn::Credential.from_get(payload.fetch("credential"))
    match = settings.store.find_by_credential_id(webauthn_credential.id)
    raise ApiError.new("このサイトに登録されたパスキーではありません", 404) unless match

    user_key, user, stored_credential = match
    requested_user_key = session[:authentication_user_key]
    if requested_user_key && requested_user_key != user_key
      raise ApiError.new("選択されたパスキーは入力したユーザー名と一致しません", 401)
    end

    unless user_handle_matches?(webauthn_credential.user_handle, user.fetch("handle"))
      raise ApiError.new("パスキーのユーザーハンドルが一致しません", 401)
    end

    webauthn_credential.verify(
      challenge,
      public_key: Base64.strict_decode64(stored_credential.fetch("public_key")),
      sign_count: stored_credential.fetch("sign_count", 0),
      user_verification: true
    )

    settings.store.update_sign_count(webauthn_credential.id, webauthn_credential.sign_count)
    clear_authentication_challenge!
    session[:user_key] = user_key
    json_response(ok: true, redirect: "/account")
  rescue KeyError
    raise ApiError.new("ログインレスポンスが不足しています", 400)
  end

  error ApiError do
    exception = env.fetch("sinatra.error")
    json_response({ error: exception.message }, exception.status_code)
  end

  error WebAuthn::Error do
    exception = env.fetch("sinatra.error")
    clear_registration_challenge!
    clear_authentication_challenge!
    json_response({ error: "パスキーを検証できませんでした: #{exception.message}" }, 401)
  end

  error do
    exception = env.fetch("sinatra.error")
    warn "#{exception.class}: #{exception.message}\n#{Array(exception.backtrace).first(8).join("\n")}"
    if request.path.start_with?("/api/")
      json_response({ error: "サーバーでエラーが発生しました" }, 500)
    else
      status 500
      erb :error
    end
  end
end
