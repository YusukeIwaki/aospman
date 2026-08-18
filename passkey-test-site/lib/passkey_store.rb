require "base64"
require "fileutils"
require "json"
require "securerandom"
require "time"

class PasskeyStore
  EMPTY_DATA = { "users" => {} }.freeze

  def initialize(path)
    @path = File.expand_path(path)
    @lock_path = "#{@path}.lock"
    FileUtils.mkdir_p(File.dirname(@path))
  end

  def find_user(username)
    key = normalize(username)
    read { |data| deep_copy(data.dig("users", key)) }
  end

  def ensure_user(username, handle:)
    key = normalize(username)
    update do |data|
      data["users"][key] ||= {
        "name" => username.strip,
        "handle" => handle,
        "credentials" => [],
        "created_at" => Time.now.utc.iso8601
      }
      deep_copy(data["users"][key])
    end
  end

  def find_by_credential_id(credential_id)
    read do |data|
      data.fetch("users", {}).each do |key, user|
        credential = user.fetch("credentials", []).find { |item| item["id"] == credential_id }
        return [key, deep_copy(user), deep_copy(credential)] if credential
      end
      nil
    end
  end

  def add_credential(username, id:, public_key:, sign_count:, transports:)
    key = normalize(username)
    update do |data|
      if credential_id_taken?(data, id)
        raise ArgumentError, "このパスキーはすでに登録されています"
      end

      user = data.dig("users", key)
      raise KeyError, "登録対象のユーザーが見つかりません" unless user

      user["credentials"] << {
        "id" => id,
        "public_key" => Base64.strict_encode64(public_key),
        "sign_count" => Integer(sign_count || 0),
        "transports" => Array(transports).map(&:to_s).uniq,
        "created_at" => Time.now.utc.iso8601
      }
    end
  end

  def update_sign_count(credential_id, sign_count)
    update do |data|
      data.fetch("users", {}).each_value do |user|
        credential = user.fetch("credentials", []).find { |item| item["id"] == credential_id }
        next unless credential

        credential["sign_count"] = Integer(sign_count || 0)
        break
      end
    end
  end

  private

  def normalize(username)
    username.to_s.strip.downcase
  end

  def read
    with_lock(File::LOCK_SH) { yield load_data }
  end

  def update
    with_lock(File::LOCK_EX) do
      data = load_data
      result = yield data
      persist(data)
      result
    end
  end

  def with_lock(mode)
    File.open(@lock_path, File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(mode)
      yield
    ensure
      lock.flock(File::LOCK_UN)
    end
  end

  def load_data
    return deep_copy(EMPTY_DATA) unless File.exist?(@path)

    parsed = JSON.parse(File.read(@path))
    parsed["users"] ||= {}
    parsed
  rescue JSON::ParserError => e
    warn "Passkey store is corrupt: #{e.message}"
    raise
  end

  def persist(data)
    temporary_path = "#{@path}.tmp-#{Process.pid}-#{SecureRandom.hex(4)}"
    File.write(temporary_path, JSON.pretty_generate(data), mode: "wb", perm: 0o600)
    File.rename(temporary_path, @path)
  ensure
    FileUtils.rm_f(temporary_path) if temporary_path && File.exist?(temporary_path)
  end

  def credential_id_taken?(data, credential_id)
    data.fetch("users", {}).values.any? do |user|
      user.fetch("credentials", []).any? { |credential| credential["id"] == credential_id }
    end
  end

  def deep_copy(value)
    value.nil? ? nil : JSON.parse(JSON.generate(value))
  end
end
