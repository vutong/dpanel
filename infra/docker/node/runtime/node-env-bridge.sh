#!/bin/sh
# Map site .env values to NUXT_* for Nitro runtimeConfig overrides at process start.
# (NUXT_* names are required by Nitro/Nuxt apps — keep them even though the service is node-*.)

_env_set_if_empty() {
  key="$1"
  val="$2"
  eval "current=\${$key-}"
  if [ -z "$current" ] && [ -n "$val" ]; then
    export "$key=$val"
  fi
}

_env_set_if_empty NUXT_SESSION_SECRET "$SESSION_SECRET"
_env_set_if_empty NUXT_MONGODB_URI "$MONGODB_URI"
_env_set_if_empty NUXT_MONGODB_DB_NAME "$MONGODB_DB_NAME"
_env_set_if_empty NUXT_HUB_BASE_DOMAIN "$HUB_BASE_DOMAIN"
_env_set_if_empty NUXT_ADMIN_HOST "$ADMIN_HOST"
_env_set_if_empty NUXT_APP_PORT "$APP_PORT"
_env_set_if_empty NUXT_GOOGLE_CLIENT_ID "$GOOGLE_CLIENT_ID"
_env_set_if_empty NUXT_GOOGLE_CLIENT_SECRET "$GOOGLE_CLIENT_SECRET"
_env_set_if_empty NUXT_GOOGLE_REDIRECT_URI "$GOOGLE_REDIRECT_URI"
_env_set_if_empty NUXT_APP_URL "$APP_URL"
_env_set_if_empty NUXT_PAYPAL_PLAN_MODE "$PAYPAL_PLAN_MODE"
_env_set_if_empty NUXT_PAYPAL_PLAN_CURRENCY "$PAYPAL_PLAN_CURRENCY"
_env_set_if_empty NUXT_PAYPAL_PLAN_SANDBOX_CLIENT_ID "$PAYPAL_PLAN_SANDBOX_CLIENT_ID"
_env_set_if_empty NUXT_PAYPAL_PLAN_SANDBOX_SECRET "$PAYPAL_PLAN_SANDBOX_SECRET"
_env_set_if_empty NUXT_PAYPAL_PLAN_SANDBOX_WEBHOOK_ID "$PAYPAL_PLAN_SANDBOX_WEBHOOK_ID"
_env_set_if_empty NUXT_PAYPAL_PLAN_LIVE_CLIENT_ID "$PAYPAL_PLAN_LIVE_CLIENT_ID"
_env_set_if_empty NUXT_PAYPAL_PLAN_LIVE_SECRET "$PAYPAL_PLAN_LIVE_SECRET"
_env_set_if_empty NUXT_PAYPAL_PLAN_LIVE_WEBHOOK_ID "$PAYPAL_PLAN_LIVE_WEBHOOK_ID"
_env_set_if_empty NUXT_FCM_SERVICE_ACCOUNT_JSON "$FCM_SERVICE_ACCOUNT_JSON"
_env_set_if_empty NUXT_FCM_SERVICE_ACCOUNT_PATH "$FCM_SERVICE_ACCOUNT_PATH"
_env_set_if_empty NUXT_SYSTEM_ADMIN_EMAILS "$SYSTEM_ADMIN_EMAILS"
_env_set_if_empty NUXT_OBJECT_STORAGE_BUCKET "$OBJECT_STORAGE_BUCKET"
_env_set_if_empty NUXT_OBJECT_STORAGE_ACCESS_KEY_ID "$OBJECT_STORAGE_ACCESS_KEY_ID"
_env_set_if_empty NUXT_OBJECT_STORAGE_SECRET_ACCESS_KEY "$OBJECT_STORAGE_SECRET_ACCESS_KEY"
_env_set_if_empty NUXT_OBJECT_STORAGE_ENDPOINT "$OBJECT_STORAGE_ENDPOINT"
_env_set_if_empty NUXT_PUBLIC_HUB_BASE_DOMAIN "$HUB_BASE_DOMAIN"
_env_set_if_empty NUXT_PUBLIC_ADMIN_HOST "$ADMIN_HOST"
_env_set_if_empty NUXT_PUBLIC_CDN_MEDIA_URL "$CDN_MEDIA_URL"
