ENV["RACK_ENV"] = "test"
ENV["WEBAUTHN_ORIGIN"] = "http://example.org"
ENV["WEBAUTHN_RP_ID"] = "example.org"
ENV["SESSION_SECRET"] = "test-session-secret-#{'x' * 64}"

require "fileutils"
require "minitest/autorun"
require "rack/test"
require "tmpdir"
require "webauthn/fake_client"

TEST_DATA_DIR = Dir.mktmpdir("passkey-test")
ENV["PASSKEY_STORE_PATH"] = File.join(TEST_DATA_DIR, "passkeys.json")

require_relative "../app"

class PasskeyTestAppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    PasskeyTestApp
  end

  def setup
    FileUtils.rm_f(ENV.fetch("PASSKEY_STORE_PATH"))
    FileUtils.rm_f("#{ENV.fetch('PASSKEY_STORE_PATH')}.lock")
    clear_cookies
  end

  def json_post(path, payload)
    post path, JSON.generate(payload), "CONTENT_TYPE" => "application/json"
  end

  def parsed_body
    JSON.parse(last_response.body)
  end

  def test_healthcheck
    get "/health"

    assert last_response.ok?
    assert_equal({ "status" => "ok" }, parsed_body)
  end

  def test_home_has_autofill_annotated_username_field
    get "/"

    assert last_response.ok?
    assert_includes last_response.body, 'autocomplete="username webauthn"'
    assert_includes last_response.body, "パスキーを作成"
  end

  def test_account_requires_login
    get "/account"

    assert last_response.redirect?
    assert_equal "http://example.org/", last_response.location
  end

  def test_registration_options_are_for_a_discoverable_credential
    json_post "/api/register/options", username: "test-user"

    assert last_response.ok?, last_response.body
    options = parsed_body.fetch("publicKey")
    assert_equal "required", options.dig("authenticatorSelection", "residentKey")
    assert_equal "required", options.dig("authenticatorSelection", "userVerification")
    assert_equal "example.org", options.dig("rp", "id")
    refute_empty options.fetch("challenge")
  end

  def test_usernameless_login_options_have_no_allow_list
    json_post "/api/login/options", {}

    assert last_response.ok?, last_response.body
    options = parsed_body.fetch("publicKey")
    assert_equal "required", options.fetch("userVerification")
    assert_equal [], options.fetch("allowCredentials")
  end

  def test_api_rejects_wrong_content_type
    post "/api/login/options", "{}"

    assert_equal 415, last_response.status
    assert_includes parsed_body.fetch("error"), "application/json"
  end

  def test_complete_registration_logout_and_login_flow
    client = WebAuthn::FakeClient.new("http://example.org")

    json_post "/api/register/options", username: "flow-user"
    registration_options = parsed_body.fetch("publicKey")
    registration_credential = client.create(
      challenge: registration_options.fetch("challenge"),
      rp_id: "example.org",
      user_verified: true
    )

    json_post "/api/register/verify", credential: registration_credential
    assert last_response.ok?, last_response.body

    get "/account"
    assert last_response.ok?
    assert_includes last_response.body, "flow-user"

    post "/logout"
    assert last_response.redirect?

    json_post "/api/login/options", username: "flow-user"
    authentication_options = parsed_body.fetch("publicKey")
    stored_user = PasskeyTestApp.settings.store.find_user("flow-user")
    user_handle = Base64.urlsafe_decode64(stored_user.fetch("handle"))
    authentication_credential = client.get(
      challenge: authentication_options.fetch("challenge"),
      rp_id: "example.org",
      user_verified: true,
      user_handle: user_handle,
      allow_credentials: authentication_options.fetch("allowCredentials").map { |item| item.fetch("id") }
    )

    json_post "/api/login/verify", credential: authentication_credential
    assert last_response.ok?, last_response.body

    get "/account"
    assert last_response.ok?
    assert_includes last_response.body, "ログインできました"
  end
end
