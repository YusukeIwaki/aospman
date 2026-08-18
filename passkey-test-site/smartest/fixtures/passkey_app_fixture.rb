# frozen_string_literal: true

require "fileutils"
require "playwright"
require "smartest/rack"
require "socket"
require "tmpdir"

module PasskeyE2E
  HOST = "127.0.0.1"
  BROWSER_HOST = "localhost"
  DATA_DIR = Dir.mktmpdir("passkey-smartest-e2e")

  listener = TCPServer.new(HOST, 0)
  PORT = listener.local_address.ip_port
  listener.close

  BASE_URL = "http://#{BROWSER_HOST}:#{PORT}"
  STORE_PATH = File.join(DATA_DIR, "passkeys.json")
end

ENV["RACK_ENV"] = "test"
ENV["WEBAUTHN_ORIGIN"] = PasskeyE2E::BASE_URL
ENV["WEBAUTHN_RP_ID"] = PasskeyE2E::BROWSER_HOST
ENV["SESSION_SECRET"] = "smartest-e2e-session-secret-#{'x' * 64}"
ENV["PASSKEY_STORE_PATH"] = PasskeyE2E::STORE_PATH

require_relative "../../app"

class PasskeyAppFixture < Smartest::Fixture
  suite_fixture :rack_server do
    server = Smartest::Rack::TestServer.new(
      app: PasskeyTestApp,
      host: PasskeyE2E::HOST,
      port: PasskeyE2E::PORT
    )
    server.start
    on_teardown do
      server.stop
      server.wait_for_stopped
      FileUtils.remove_entry(PasskeyE2E::DATA_DIR) if Dir.exist?(PasskeyE2E::DATA_DIR)
    end
    server.wait_for_ready

    server
  end

  suite_fixture :base_url do |rack_server:|
    rack_server
    PasskeyE2E::BASE_URL
  end

  suite_fixture :browser do
    execution = Playwright.create(
      playwright_cli_executable_path: ENV.fetch(
        "PLAYWRIGHT_CLI_EXECUTABLE_PATH",
        "./node_modules/.bin/playwright"
      )
    )
    on_teardown { execution.stop }

    browser = execution.playwright.public_send(selected_browser_type).launch(**browser_launch_options)
    on_teardown { browser.close }
    browser
  end

  fixture :clean_store do
    FileUtils.rm_f(PasskeyE2E::STORE_PATH)
    FileUtils.rm_f("#{PasskeyE2E::STORE_PATH}.lock")
    true
  end

  fixture :browser_context do |base_url:, browser:, clean_store:|
    clean_store
    context = browser.new_context(baseURL: base_url)
    on_teardown { context.close }
    context.credentials.install
    context
  end

  fixture :page do |browser_context:|
    page = browser_context.new_page
    on_teardown { page.close }
    page
  end

  private

  def selected_browser_type
    case ENV.fetch("BROWSER", "chromium")
    when "firefox"
      :firefox
    when "webkit"
      :webkit
    else
      :chromium
    end
  end

  def browser_launch_options
    options = { headless: !%w[0 false].include?(ENV.fetch("HEADLESS", "true")) }
    slow_mo = ENV.fetch("SLOW_MO", "0").to_i
    options[:slowMo] = slow_mo if slow_mo.positive?
    options
  end
end
