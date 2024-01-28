#!/usr/bin/env bash

set -e
\unalias -a
IFS=$'\n'

input_text="${1:-what is google gemini ai?}"
input_image="${2}"              # can be url or local image
mimeType="${3:-image/jpeg}"     # https://cloud.google.com/vertex-ai/docs/generative-ai/model-reference/gemini#gemini-pro for full list
input_pdf="${4}"                # can be url or local pdf
temperature="${5:-0.1}"         # 0-1 A temperature of 0 is deterministic: the highest probability response is always selected.
topP="${6:-0.1}"                # 0-1 Specify a lower value for less random responses and a higher value for more random responses.
maxOutputTokens="${7:-2048}"    # gemini-pro: 1-8192; gemini-pro-vision: 1-2048

function print_error { printf '%b' "\e[31m${1}\e[0m\n" >&2; }
function print_green { printf '%b' "\e[32m${1}\e[0m\n" 2>&1; }
function check_command { command -v "$1" &>/dev/null; }
HOME="${HOME:-$(eval echo ~$USER)}"

check_command uname || { print_error "command uname isn't installed"; exit 1; }
check_command curl || { print_error "command curl isn't installed"; exit 1; }
check_command tar || { print_error "command tar isn't installed"; exit 1; }
check_command grep || { print_error "command grep isn't installed"; exit 1; }
check_command awk || { print_error "command awk isn't installed"; exit 1; }
check_command tr || { print_error "command tr isn't installed"; exit 1; }
check_command openssl || { print_error "command openssl isn't installed"; exit 1; }
check_command convert \
  || {
    print_error "command convert isn't installed. imagemagick will be installed if you have installed brew"
    if check_command brew; then
      brew install imagemagick >/dev/null \
        && { print_green 'imagemagick successfully installed by brew'; true; } \
        || { print_error 'imagemagick cannot be installed'; exit 1; }
    else
      print_error "imagemagick cannot be installed because you did not install brew. Try install brew first and re-run this script"; exit 1
    fi
  }
check_command jq \
  || {
    print_error "command jq isn't installed. jq will be installed if you have installed brew"
    if check_command brew; then
      brew install jq >/dev/null \
        && { print_green 'jq successfully installed by brew'; true; } \
        || { print_error 'jq cannot be installed'; exit 1; }
    else
      print_error "jq cannot be installed because you did not install brew. Try install brew first and re-run this script"; exit 1
    fi
  }

gcloud_dir="$HOME"

if ! [ -d "$gcloud_dir/google-cloud-sdk" ]; then

  case "$(uname -o)" in
    *Darwin*)
      if [ "$(uname -m)" = 'arm64' -o "$(uname -m)" = 'aarch64' ]; then
        gcloud_cli_url=https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-461.0.0-darwin-arm.tar.gz
      elif [ "$(uname -m)" = 'x86_64' -o "$(uname -m)" = 'amd64' ]; then
        gcloud_cli_url=https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-461.0.0-darwin-x86_64.tar.gz
      else
        print_error 'need 64 bit here'; exit 1;
      fi ;;
    *)
        print_error 'need macos here'; exit 1
        ;;
  esac

  resp="$(curl -sL "$gcloud_cli_url" -o "$gcloud_dir/${gcloud_cli_url##*/}" -w '%{http_code}')"
  [ "$resp" != '200' ] && { print_error 'cannot download gcloud'; exit 1; }
  unset resp

  tar -xzf "$gcloud_dir/${gcloud_cli_url##*/}" -C "$gcloud_dir" || { print_error 'cannot extract tar file'; exit 1; }
  rm -rf "$gcloud_dir/${gcloud_cli_url##*/}"

  if [ -n "$SHELL" ]; then
    login_shell="$(printf '%b' "$SHELL\n")"
    profile_file=''
    case "${login_shell##*/}" in
      bash)
        profile_file='.bashrc'
          ;;
      zsh)
        profile_file='.zshrc'
          ;;
      *)
        print_error "your login shell isn't bash or zsh"
          ;;
    esac

    [ -n "$profile_file" -a -w "$HOME/$profile_file" ] \
      && printf '%b' "export gcloud_dir='$gcloud_dir'\n" >> "$HOME/$profile_file" \
      && printf '%b' 'export PATH="$gcloud_dir/google-cloud-sdk/bin:$PATH"\n' >> "$HOME/$profile_file" \
      || print_error 'cannot update profile file'
  else
    print_error '$SHELL is unset'
  fi
fi

IFS=':'
i=0
for p in $PATH; do
  [ "$p" = "$gcloud_dir/google-cloud-sdk/bin" ] && let i++ && break
done
IFS=$'\n'

[ "$i" = '0' ] && export PATH="$gcloud_dir/google-cloud-sdk/bin:$PATH"

gcloud_config_json="$HOME/.config/gcloud/application_default_credentials.json"
if [ -e "$gcloud_config_json" ]; then
  if ! grep -iE 'client_secret' "$gcloud_config_json" &>/dev/null; then
    gcloud init \
      && gcloud components update \
      && gcloud components install beta \
      && gcloud auth application-default login \
      && gcloud auth application-default print-access-token \
      || { print_error 'cannot login or print access token'; exit 1; }
  fi
  # gcloud beta services list --available
  if ! gcloud beta services list --enabled | grep -iE 'aiplatform.googleapis.com' &>/dev/null ; then
    gcloud beta services enable aiplatform.googleapis.com || { print_error 'cannot enable aiplatform'; exit 1; }
  fi
else
  gcloud init \
    && gcloud components update \
    && gcloud components install beta \
    && gcloud auth application-default login \
    && gcloud auth application-default print-access-token \
    || { print_error 'cannot login or print access token'; exit 1; }
  gcloud beta services enable aiplatform.googleapis.com || { print_error 'cannot enable aiplatform'; exit 1; }
fi

[ -e "$gcloud_config_json" ] \
  && gcloud config set disable_usage_reporting true &>/dev/null \
  && PROJECT_ID="$(grep -iE 'quota_project_id' "$gcloud_config_json" | awk '{ print $2 }' | tr -d '"' | tr -d ',' )" \
  || { print_error 'cannot find gcloud config or project id in the config'; exit 1; }

if [ -z "$input_image" -a -z "$input_pdf" ]; then
  MODEL_ID='gemini-pro'

  json="{
    'contents': {
      'role': 'user',
      'parts': {
          'text': '"$input_text"'
      }
    },"
elif [ -n "$input_image" -a -z "$input_pdf" ] || [ -z "$input_image" -a -n "$input_pdf" ]; then
  MODEL_ID='gemini-pro-vision'

  if [ -n "$input_pdf" ]; then
    data_type='inlineData'
    data_source='data'

    ran_num="$RANDOM"
    mkdir -p "/tmp/$ran_num" || { print_error 'cannot create temp dir'; exit 1; }

    if [ "${input_pdf:0:8}" = 'https://' -o "${input_pdf:0:7}" = 'http://' ]; then
      resp="$(curl -sL "$input_pdf" -o /tmp/tmp_pdf.pdf -w '%{http_code}')"
      [ "$resp" != '200' ] && { print_error 'cannot download pdf'; exit 1; }
      unset resp
      input_pdf=/tmp/tmp_pdf.pdf
    fi

    convert -density 300 -quality 100 "$input_pdf" "/tmp/$ran_num/temp_jpg-%d.jpg" \
      && convert -background none -gravity Center "/tmp/$ran_num/temp_jpg-*.jpg" -append "/tmp/$ran_num/temp_jpg.jpg" \
      || { print_error 'cannot convert pdf to jpg'; exit 1; }

    image="$(openssl base64 < "/tmp/$ran_num/temp_jpg.jpg" | tr -d '\n')" \
        || { print_error 'cannot transfer image to base64'; exit 1; }

    [ -e /tmp/tmp_pdf ] && rm -f /tmp/tmp_pdf
    rm -rf "/tmp/$ran_num"; unset ran_num

  elif [ "${input_image:0:5}" = 'gs://' ]; then
    data_type='fileData'
    data_source='fileUri'
    image="$input_image"
  else
    data_type='inlineData'
    data_source='data'

    if [ "${input_image:0:8}" = 'https://' -o "${input_image:0:7}" = 'http://' ]; then
      resp="$(curl -sL "$input_image" -o /tmp/tmp_image -w '%{http_code}')"
      [ "$resp" != '200' ] && { print_error 'cannot download image'; exit 1; }
      unset resp
      input_image=/tmp/tmp_image
    fi

    image="$(openssl base64 < "$input_image" | tr -d '\n')" \
      || { print_error 'cannot transfer image to base64'; exit 1; }
    [ -e /tmp/tmp_image ] && rm -f /tmp/tmp_image
  fi
  json="{
    'contents': {
      'role': 'user',
      'parts': [
        {
          '"$data_type"': {
            'mimeType': '"$mimeType"',
            '"$data_source"': '"$image"'
            }
          },
        {
          'text': '"$input_text"'
        }
      ]
    },"
else
  print_error 'input_image and input_pdf cannot have values at the same time'; exit 1
fi

json_concat="${json}
  'safety_settings': {
    'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
    'threshold': 'BLOCK_LOW_AND_ABOVE'
  },
  'generation_config': {
    'temperature': "$temperature",
    'topP': "$topP",
    'maxOutputTokens': "$maxOutputTokens"
  }
}"

ran_num="$RANDOM"
mkdir -p "/tmp/$ran_num" || { print_error 'cannot create temp dir'; exit 1; }
printf '%s' "$json_concat" > "/tmp/$ran_num/json.txt" || { print_error 'cannot concat json'; exit 1; }

resp="$( \
  curl -s \
  -X POST \
  -H "Authorization: Bearer $(gcloud auth application-default print-access-token)" \
  -H 'Content-Type: application/json; charset=utf-8' \
  -d "@/tmp/$ran_num/json.txt" \
  "https://us-central1-aiplatform.googleapis.com/v1/projects/${PROJECT_ID}/locations/us-central1/publishers/google/models/${MODEL_ID}:streamGenerateContent" \
)"

rm -f "/tmp/$ran_num/json.txt"; unset ran_num

[ -n "$resp" ] \
  && print_green "$(printf '%s' "$resp" | jq .[].candidates | jq .[].content.parts | jq .[].text | tr -d '"\n"')" \
  || { print_error 'no response or no text content'; exit 1; }
