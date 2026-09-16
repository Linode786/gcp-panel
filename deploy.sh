#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="${SERVICE_NAME:-pm-panel}"
REPO_NAME="${REPO_NAME:-pm-panel-repo}"
DEFAULT_REGION="${REGION:-asia-southeast1}"
DEFAULT_BACKEND="${DEFAULT_BACKEND:-cffdg.mindfreak.online:700}"
DEFAULT_ROUTES="${ROUTES:-/vp-us=cffdg.mindfreak.online:700,/vp-ge=fgfja.mindfreak.online:700,/vp-uk=dbaai.mindfreak.online:700,/vp-sg=dcafc.mindfreak.online:700}"
MEMORY="${MEMORY:-512Mi}"
CPU="${CPU:-1}"
CONCURRENCY="${CONCURRENCY:-80}"
MIN_INSTANCES="${MIN_INSTANCES:-0}"
MAX_INSTANCES="${MAX_INSTANCES:-2}"
TIMEOUT="${TIMEOUT:-3600}"

choose_region() {
  echo "Choose Cloud Run region:"
  echo "1) southamerica-east1  Brazil"
  echo "2) europe-southwest1   Spain"
  echo "3) us-central1         United States"
  echo "4) asia-southeast1     Singapore"
  echo "5) asia-southeast2     Jakarta"
  echo "6) me-central1         Doha"
  read -r -p "Enter 1, 2, 3, 4, 5, or 6 [$DEFAULT_REGION]: " choice

  case "$choice" in
    1) REGION="southamerica-east1" ;;
    2) REGION="europe-southwest1" ;;
    3) REGION="us-central1" ;;
    4) REGION="asia-southeast1" ;;
    5) REGION="asia-southeast2" ;;
    6) REGION="me-central1" ;;
    *) REGION="$DEFAULT_REGION" ;;
  esac
}

read_config() {
  read -r -p "Enter default backend [$DEFAULT_BACKEND]: " input_default_backend
  DEFAULT_BACKEND="${input_default_backend:-$DEFAULT_BACKEND}"

  read -r -p "Enter routes [$DEFAULT_ROUTES]: " input_routes
  ROUTES="${input_routes:-$DEFAULT_ROUTES}"
}

read_runtime_settings() {
  echo "Runtime settings:"

  read -r -p "Memory [$MEMORY]: " input_memory
  MEMORY="${input_memory:-$MEMORY}"

  read -r -p "CPU [$CPU]: " input_cpu
  CPU="${input_cpu:-$CPU}"

  read -r -p "Concurrency [$CONCURRENCY]: " input_concurrency
  CONCURRENCY="${input_concurrency:-$CONCURRENCY}"

  read -r -p "Min instances [$MIN_INSTANCES]: " input_min_instances
  MIN_INSTANCES="${input_min_instances:-$MIN_INSTANCES}"

  read -r -p "Max instances [$MAX_INSTANCES]: " input_max_instances
  MAX_INSTANCES="${input_max_instances:-$MAX_INSTANCES}"

  read -r -p "Timeout seconds [$TIMEOUT]: " input_timeout
  TIMEOUT="${input_timeout:-$TIMEOUT}"
}

image_name() {
  IMAGE="$REGION-docker.pkg.dev/$GOOGLE_CLOUD_PROJECT/$REPO_NAME/$SERVICE_NAME:latest"
}

service_exists() {
  gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" \
    --format="value(metadata.name)" >/dev/null 2>&1
}

enable_services() {
  gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
}

ensure_repo() {
  gcloud artifacts repositories create "$REPO_NAME" \
    --repository-format=docker \
    --location="$REGION" \
    --description="Cloud Run proxy images" 2>/dev/null || true
}

build_image() {
  image_name
  gcloud builds submit --tag "$IMAGE"
}

deploy_service() {
  image_name
  gcloud run deploy "$SERVICE_NAME" \
    --image "$IMAGE" \
    --platform managed \
    --region "$REGION" \
    --allow-unauthenticated \
    --execution-environment gen2 \
    --memory "$MEMORY" \
    --cpu "$CPU" \
    --concurrency "$CONCURRENCY" \
    --min-instances "$MIN_INSTANCES" \
    --max-instances "$MAX_INSTANCES" \
    --timeout "$TIMEOUT" \
    --set-env-vars "^@^DEFAULT_BACKEND=$DEFAULT_BACKEND@ROUTES=$ROUTES"

  echo
  echo "Done. Your Cloud Run URL:"
  gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" \
    --format="value(status.url)"
}

update_config_only() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]."
    read -r -p "Install/redeploy it now? [y/N]: " install_now
    case "$install_now" in
      y|Y|yes|YES)
        enable_services
        ensure_repo
        build_image
        deploy_service
        ;;
      *)
        echo "Choose option 1 later to install/redeploy the service."
        ;;
    esac
    return 0
  fi

  gcloud run services update "$SERVICE_NAME" \
    --region "$REGION" \
    --set-env-vars "^@^DEFAULT_BACKEND=$DEFAULT_BACKEND@ROUTES=$ROUTES"
}

update_runtime_settings() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]."
    echo "Choose option 1 first to install/redeploy the service."
    return 0
  fi

  gcloud run services update "$SERVICE_NAME" \
    --region "$REGION" \
    --memory "$MEMORY" \
    --cpu "$CPU" \
    --concurrency "$CONCURRENCY" \
    --min-instances "$MIN_INSTANCES" \
    --max-instances "$MAX_INSTANCES" \
    --timeout "$TIMEOUT"
}

test_service() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]."
    echo "Choose option 1 first to install/redeploy the service."
    return 0
  fi

  url="$(gcloud run services describe "$SERVICE_NAME" --region "$REGION" --format="value(status.url)")"
  echo "Testing $url"
  echo

  for route in vp-us vp-ge vp-uk vp-sg; do
    code="$(curl --http1.1 -k -s -o /dev/null -w "%{http_code}" "$url/$route")"
    echo "$route OVPN  -> $code"

    code="$(curl --http1.1 -k -s -o /dev/null -w "%{http_code}" "$url/$route/ssh")"
    echo "$route SSH   -> $code"

    code="$(curl --http1.1 -k -s -o /dev/null -w "%{http_code}" \
      -H "Connection: Upgrade" \
      -H "Upgrade: websocket" \
      -H "Sec-WebSocket-Version: 13" \
      -H "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
      "$url/$route/vless")"
    echo "$route VLESS -> $code"
    echo
  done
}

show_logs() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]."
    echo "Choose option 1 first to install/redeploy the service."
    return 0
  fi

  gcloud run services logs read "$SERVICE_NAME" \
    --region "$REGION" \
    --limit 50
}

delete_service() {
  if ! service_exists; then
    echo "Service [$SERVICE_NAME] was not found in region [$REGION]. Nothing to delete."
    return 0
  fi

  gcloud run services delete "$SERVICE_NAME" \
    --region "$REGION" \
    --quiet
}

delete_image_repo() {
  gcloud artifacts repositories delete "$REPO_NAME" \
    --location="$REGION" \
    --quiet
}

while true; do
  echo
  echo "Cloud Run Proxy Menu"
  echo "1) Install or redeploy"
  echo "2) Change host/path config only"
  echo "3) Change runtime settings only"
  echo "4) Test OVPN, SSH, VLESS"
  echo "5) Show logs"
  echo "6) Delete Cloud Run service"
  echo "7) Delete image repository"
  echo "8) Exit"
  read -r -p "Choose: " action
  echo

  case "$action" in
    1)
      choose_region
      read_config
      read_runtime_settings
      enable_services
      ensure_repo
      build_image
      deploy_service
      ;;
    2)
      choose_region
      read_config
      update_config_only
      ;;
    3)
      choose_region
      read_runtime_settings
      update_runtime_settings
      ;;
    4)
      choose_region
      test_service
      ;;
    5)
      choose_region
      show_logs
      ;;
    6)
      choose_region
      delete_service
      ;;
    7)
      choose_region
      delete_image_repo
      ;;
    8)
      exit 0
      ;;
    *)
      echo "Invalid choice."
      ;;
  esac
done
