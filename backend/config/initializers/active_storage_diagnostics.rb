# frozen_string_literal: true

# Makes the Active Storage service choice observable at boot.
#
# In production the bucket behind an attachment (proof screenshots, the Manual
# QR image) is Cloudflare R2, but the selection is silent: a partial R2 config
# quietly falls back to the container filesystem, and AWS_* + R2_* together
# silently pick :amazon. Both end as "image upload failed" with no reason, so
# log exactly what was detected — plus what to run to verify it end to end:
#
#   bin/rails storage:check
Rails.application.config.after_initialize do
  logger = Rails.logger
  next unless logger

  chosen = Rails.application.config.active_storage.service
  endpoint = ENV["CLOUDFLARE_ENDPOINT"].presence || ENV["R2_ENDPOINT"].presence
  access_key = ENV["CLOUDFLARE_ACCESS_KEY_ID"].presence || ENV["R2_ACCESS_KEY_ID"].presence
  secret_key = ENV["CLOUDFLARE_SECRET_ACCESS_KEY"].presence || ENV["R2_SECRET_ACCESS_KEY"].presence
  bucket = ENV["CLOUDFLARE_BUCKET"].presence || ENV["R2_BUCKET"].presence

  aws_configured = ENV["AWS_ACCESS_KEY_ID"].present? && ENV["AWS_SECRET_ACCESS_KEY"].present?
  r2 = { "ENDPOINT" => endpoint, "ACCESS_KEY_ID" => access_key,
         "SECRET_ACCESS_KEY" => secret_key, "BUCKET" => bucket }
  r2_set = r2.count { |_k, v| v.present? }

  logger.info("[storage] Active Storage service: #{chosen.inspect}")

  if r2_set.between?(1, 3)
    logger.warn(
      "[storage] Cloudflare R2 config incomplete — missing: #{r2.select { |_k, v| v.blank? }.keys.join(', ')}. " \
      "R2 is NOT used; attachments go to #{chosen.inspect}. Run `bin/rails storage:check`."
    )
  end

  if aws_configured && r2_set == 4
    logger.warn(
      "[storage] Both AWS_* and Cloudflare R2 credentials are set — Active Storage uses :amazon. " \
      "Unset the pair you do not want (they are independent of BACKUP_R2_*)."
    )
  end

  if endpoint.present? && !endpoint.match?(%r{\Ahttps?://}i)
    logger.warn("[storage] R2/CLOUDFLARE endpoint #{endpoint.inspect} has no http(s):// scheme — uploads will fail.")
  end

  if chosen.to_s == "local" && Rails.env.production?
    logger.warn(
      "[storage] Writing attachments to the container filesystem — they are lost on redeploy. " \
      "Configure CLOUDFLARE_* (or R2_*) and run `bin/rails storage:check`."
    )
  end
end
