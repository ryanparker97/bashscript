#!/bin/bash

DEFAULT_COMPANY=$1
DEFAULT_PROFILE=$2
DEFAULT_ENV=$3

selected_env=""
profile=""

# --- COMPANY SELECTION ---
if [ ! -z "$DEFAULT_COMPANY" ] ; then
  company=$DEFAULT_COMPANY
  PROFILES_FILE="$HOME/Documents/work/$company/code/dbt_profiles/profiles.yml"
  profile=$(yq eval 'keys | .[0]' "$PROFILES_FILE")
else
  # Sorted alphabetically
  COMPANY=$(ls "$HOME/Documents/work" | sort)
  
  PS3="select company that you're working: "
  select company in $COMPANY; do
    if [ -n "$company" ]; then
      break
    else
      echo "Invalid selection. Please select a valid profile number."
    fi
  done
  echo "=========> Company selected: $company"
fi

# --- PROFILE SELECTION ---
if [ ! -z "$DEFAULT_PROFILE" ]; then
  profile=$DEFAULT_PROFILE
else
  PROFILES_FILE="$HOME/Documents/work/$company/code/dbt_profiles/profiles.yml"
  PS3="select profile: "
  
  # Sorted alphabetically
  profiles=$(yq eval 'keys | .[]' "$PROFILES_FILE" | sort)
  
  select profile in $profiles; do
    if [ -n "$profile" ]; then
      break
    else
      echo "Invalid selection. Please select a valid profile number."
    fi
  done
fi
echo "=========>Profile selected: $profile"

# --- ENVIRONMENT SELECTION ---
if [ ! -z "$DEFAULT_ENV" ]; then
  selected_env=$DEFAULT_ENV
else
  PS3="select environment: "
  
  # Sorted alphabetically explicitly here
  envs=$(yq eval ".${profile}.outputs | keys | .[]" "$PROFILES_FILE" | sort)
  
  select env in $envs; do
    if [[ -n "$env" ]]; then
      selected_env=$env
      break
    else
      echo "Invalid selection, please try again."
    fi
  done
fi
echo "=========>Environment selected: $selected_env"

# --- UPDATE DBT PROFILES ---
profile_config=$(yq eval ".${profile}.outputs.${selected_env}" "$PROFILES_FILE")

cat <<EOF >"$HOME/.dbt/profiles.yml"
${profile}:
  outputs:
    ${selected_env}:
$(echo "$profile_config" | sed 's/^/      /')  # Indent the config for proper YAML formatting
  target: ${selected_env}
EOF
