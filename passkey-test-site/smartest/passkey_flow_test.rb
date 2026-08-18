# frozen_string_literal: true

require "test_helper"
require "uri"

def register_passkey(page, username)
  page.goto("/")
  page.get_by_role("tab", name: "新規登録").click
  form = page.locator("#register-form")
  input = form.locator("input[name='username']")
  input.fill(username)
  expect(input.input_value).to eq(username)
  form.locator("button[type='submit']").click
  page.wait_for_url("**/account")
end

# @type [Playwright::Page] page
# @type [Playwright::BrowserContext] browser_context
test("パスキーを登録し、ログアウト後にユーザー名なしで再ログインできる") do |page:, browser_context:|
  username = "smartest-explicit-user"
  register_passkey(page, username)

  expect(page.get_by_role("heading", name: "ログインできました")).to be_visible
  expect(page.locator(".account-details")).to contain_text(username)
  expect(page.locator(".account-details")).to contain_text("1 件")

  credential = browser_context.credentials.get(rpId: "localhost").first
  expect(credential).not_to be_nil
  expect(credential.fetch("privateKey")).to match(/\A[A-Za-z0-9_-]+\z/)

  browser_context.credentials.delete(credential.fetch("id"))
  page.get_by_role("button", name: "ログアウトして再テスト").click
  page.wait_for_url("**/?logged_out=1")
  expect(page.get_by_role("heading", name: "パスキーでログイン")).to be_visible

  browser_context.credentials.create(
    credential.fetch("rpId"),
    id: credential.fetch("id"),
    userHandle: credential.fetch("userHandle"),
    privateKey: credential.fetch("privateKey"),
    publicKey: credential.fetch("publicKey")
  )

  page.get_by_role("button", name: "パスキーでログイン").click
  page.wait_for_url("**/account")

  expect(page.get_by_role("heading", name: "ログインできました")).to be_visible
  expect(page.locator(".account-details")).to contain_text(username)
end

# @type [Playwright::Page] page
test("Conditional Mediationで登録済みパスキーを使って再ログインできる") do |page:|
  username = "smartest-conditional-user"
  register_passkey(page, username)

  requests = []
  page.on("request", ->(request) { requests << URI(request.url).path })

  page.get_by_role("button", name: "ログアウトして再テスト").click
  page.wait_for_url("**/account")

  expect(requests).to include("/api/login/options")
  expect(requests).to include("/api/login/verify")
  expect(page.get_by_role("heading", name: "ログインできました")).to be_visible
  expect(page.locator(".account-details")).to contain_text(username)
end
