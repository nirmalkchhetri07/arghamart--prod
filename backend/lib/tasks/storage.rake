# frozen_string_literal: true

# Verifies the configured Active Storage service (Cloudflare R2 / S3 / disk)
# really can store, read back and delete a file — the check production needs
# when a screenshot or QR image upload fails.
#
#   bin/rails storage:check            # or: docker exec <web> bin/rails storage:check
#
# Prints the non-secret half of the config (endpoint host, bucket, region,
# whether credentials are present), then performs a real round trip and exits
# non-zero on failure with a hint for the usual R2 causes.
namespace :storage do
  desc "Verify the Active Storage service (Cloudflare R2 / S3 / disk) can store, read and delete files"
  task check: :environment do
    require "stringio"

    service_name = Rails.application.config.active_storage.service
    endpoint = ENV["CLOUDFLARE_ENDPOINT"].presence || ENV["R2_ENDPOINT"].presence
    bucket = ENV["CLOUDFLARE_BUCKET"].presence || ENV["R2_BUCKET"].presence
    access_key = ENV["CLOUDFLARE_ACCESS_KEY_ID"].presence || ENV["R2_ACCESS_KEY_ID"].presence
    secret_key = ENV["CLOUDFLARE_SECRET_ACCESS_KEY"].presence || ENV["R2_SECRET_ACCESS_KEY"].presence

    puts "Service  : #{service_name}"
    case service_name.to_s
    when "cloudflare"
      puts "Endpoint : #{endpoint.presence || '(MISSING)'}"
      puts "Bucket   : #{bucket.presence || '(MISSING)'}"
      puts "Region   : auto"
      puts "Access key: #{access_key ? 'set' : 'MISSING'}"
      puts "Secret key: #{secret_key ? 'set' : 'MISSING'}"
    when "amazon"
      puts "Bucket   : #{ENV['AWS_BUCKET'].presence || '(default)'}"
      puts "Region   : #{ENV['AWS_REGION'].presence || '(MISSING)'}"
      puts "Access key: #{ENV['AWS_ACCESS_KEY_ID'].present? ? 'set' : 'MISSING'}"
      puts "Secret key: #{ENV['AWS_SECRET_ACCESS_KEY'].present? ? 'set' : 'MISSING'}"
    else
      puts "Root     : #{Rails.root.join('storage')}"
    end
    puts

    payload = "spree storage check #{Time.now.utc.iso8601}\n"
    blob = nil

    begin
      blob = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(payload),
        filename: "spree-storage-check.txt",
        content_type: "text/plain"
      )
      puts "Upload   : OK (key=#{blob.key})"

      read_back = blob.download
      raise "read back returned #{read_back.bytesize} bytes, expected #{payload.bytesize}" if read_back != payload

      puts "Download : OK"
    rescue StandardError => e
      warn "FAILED   : #{e.class}: #{e.message}"
      warn
      warn "Likely causes:"
      warn "  AccessDenied / InvalidAccessKeyId -> the R2 API token needs Object Read & Write on this bucket"
      warn "  NoSuchBucket / NotFound / DNS error -> wrong R2_BUCKET name or R2_ENDPOINT account"
      warn "  NetworkingError / SocketError / timeout -> endpoint unreachable from this host"
      warn "  Invalid region / PermanentRedirect -> endpoint and region do not match (R2 uses region 'auto')"
      exit 1
    ensure
      if blob
        begin
          blob.purge
          puts "Delete   : OK"
        rescue StandardError => e
          warn "Delete   : FAILED (#{e.class}: #{e.message}) — remove spree-storage-check.txt from the bucket manually"
        end
      end
    end

    puts
    puts "OK — Active Storage can store files with the #{service_name} service."
  end
end
