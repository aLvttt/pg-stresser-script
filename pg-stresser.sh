#!/usr/bin/env bash
set -euo pipefail

ADMIN_ENV_EXPLICIT=0
for admin_var in PGADMIN_HOST PGADMIN_PORT PGADMIN_DATABASE PGADMIN_USER PGADMIN_PASSWORD; do
  if [[ -n "${!admin_var+x}" ]]; then
    ADMIN_ENV_EXPLICIT=1
    break
  fi
done

LOCAL_PGSOCKET_DIR="${LOCAL_PGSOCKET_DIR:-/var/run/postgresql}"

# ---------------- Параметры подключения для нагрузки по умолчанию (Workload connection defaults) ----------------
PGHOST="${PGHOST:-$LOCAL_PGSOCKET_DIR}"
PGPORT="${PGPORT:-5432}"
PGDATABASE="${PGDATABASE:-stresser_test}"
PGUSER="${PGUSER:-stresser_user}"
PGPASSWORD="${PGPASSWORD:-stresser_pass}"
export PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD

# ---------------- Целевые объекты (Target objects) ----------------
TEST_SCHEMA="${TEST_SCHEMA:-stresser_probe}"
TEST_TABLE="${TEST_TABLE:-sql_events}"

# ---------------- Параметры административного подключения по умолчанию (Admin connection defaults) ----------------
ADMIN_HOST="${PGADMIN_HOST:-$PGHOST}"
ADMIN_PORT="${PGADMIN_PORT:-$PGPORT}"
ADMIN_DATABASE="${PGADMIN_DATABASE:-postgres}"
ADMIN_USER="${PGADMIN_USER:-postgres}"
ADMIN_PASSWORD="${PGADMIN_PASSWORD:-}"

# ---------------- Параметры выполнения по умолчанию (Runtime defaults) ----------------
SETUP=0
RECREATE_ZONE=0
RUN_LOAD=0
DELETE_ZONE=0
MODE=""
PRESET=""
INTERACTIVE=0
RPM=10000
DURATION=60
INITIAL_ROWS=200
ONLY=""
REPORT_EVERY=5
PAYLOAD_SIZE=32
PAYLOAD_SIZE_EXPLICIT=0
SESSION_WARMUP_SECONDS=1
RUN_TAG=""

# веса (используются только если ONLY пуст или содержит несколько операций) (weights used only if ONLY is empty or has multiple ops)
W_SELECT=60
W_INSERT=25
W_UPDATE=10
W_DELETE=5

usage() {
  cat <<EOF
Usage: $0 [options]

Purpose:
  Controlled SQL event generator for PostgreSQL validation and load checks.
  Works only with the dedicated technical test zone created by the script.

Quick start:
  1) Start with no arguments (recommended):
     $0
     or
     $0 --interactive
     or
     $0 --mode prepare --admin-password secret

  2) Run SQL load against an already prepared test zone:
     $0 --mode run --preset test

  3) Delete the test zone:
     $0 --mode delete --admin-password secret

Modes:
  --mode prepare             Prepare or recreate test zone
  --mode run                 Run load against the auto-created test zone
  --mode delete              Delete test zone

Presets:
  --preset test              Small short run for quick verification (120 SQL/min, 60 sec)
  --preset base              Base workload profile (5000 SQL/min, 300 sec)
  --interactive              Start step-by-step interactive wizard

Options:
  --setup                     Alias for --mode prepare
  --delete-zone               Alias for --mode delete
  --host HOST                 Technical DB host or local socket dir (default $PGHOST)
  --port PORT                 Technical DB port (default $PGPORT)
  --database DB               Technical test database name (default $PGDATABASE)
  --user USER                 Technical test database user (default $PGUSER)
  --password PASS             Technical test database password
  --schema NAME               Technical test schema (default $TEST_SCHEMA)
  --table NAME                Technical test table (default $TEST_TABLE)
  --admin-host HOST           Admin host or local socket dir for auto prepare/delete (default $ADMIN_HOST)
  --admin-port PORT           Admin port for auto prepare/delete (default $ADMIN_PORT)
  --admin-db DB               Admin database for auto prepare/delete (default $ADMIN_DATABASE)
  --admin-user USER           Admin user for auto prepare/delete
  --admin-password PASS       Admin password for auto prepare/delete
  --rpm N                     Target SQL statements per minute (default $RPM)
  --duration SEC              Duration in seconds (default $DURATION)
  --initial-rows N            Rows seeded by prepare mode (default $INITIAL_ROWS)
  --payload-size N            Payload size for INSERT/UPDATE text fields (default $PAYLOAD_SIZE)
  --tag TAG                   Marker added only to generated workload SQL (run/seq/op)
  --only OPS                  Comma-separated: select,insert,update,delete
  --select-weight N           SELECT weight (default $W_SELECT)
  --insert-weight N           INSERT weight (default $W_INSERT)
  --update-weight N           UPDATE weight (default $W_UPDATE)
  --delete-weight N           DELETE weight (default $W_DELETE)
  --report-every SEC          Progress print period (default $REPORT_EVERY, 0 disables)
  -h|--help                   Help

Environment overrides:
  PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD
  TEST_SCHEMA TEST_TABLE
  PGADMIN_HOST PGADMIN_PORT PGADMIN_DATABASE PGADMIN_USER PGADMIN_PASSWORD

Examples:
  $0
  $0 --interactive
  $0 --mode prepare --admin-password secret
  $0 --mode run --preset test
  $0 --mode run --preset base
  $0 --mode run --rpm 1200 --duration 60 --only select,insert
  $0 --mode delete --admin-password secret
  PGADMIN_USER=postgres PGADMIN_PASSWORD=secret $0 --mode prepare
EOF
}

die() { echo "ERROR: $*" >&2; exit 1; }
note() { echo "NOTE: $*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }
rule() { echo "--------------------------------------------------"; }

is_uint() { [[ "$1" =~ ^[0-9]+$ ]]; }
is_posint() { is_uint "$1" && (( $1 > 0 )); }
is_nonnegint() { is_uint "$1"; }
is_ident() { [[ "$1" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; }

require_ident() {
  local label="$1" value="$2"
  is_ident "$value" || die "$label must match [A-Za-z_][A-Za-z0-9_]*, got: $value"
}

escape_sql_literal() {
  local s="${1//\'/\'\'}"
  printf "%s" "$s"
}

now_dt() { date "+%Y-%m-%d %H:%M:%S"; }

test_admin_connection() {
  PGHOST="$ADMIN_HOST" \
  PGPORT="$ADMIN_PORT" \
  PGDATABASE="$ADMIN_DATABASE" \
  PGUSER="$ADMIN_USER" \
  PGPASSWORD="$ADMIN_PASSWORD" \
  psql -v ON_ERROR_STOP=1 -qAt -c "SELECT 1;" >/dev/null 2>&1
}

prompt_with_default() {
  local label="$1"
  local default_value="$2"
  local answer=""
  read -r -p "$label [$default_value]: " answer
  if [[ -n "$answer" ]]; then
    printf "%s" "$answer"
  else
    printf "%s" "$default_value"
  fi
}

prompt_secret_with_default() {
  local label="$1"
  local default_value="$2"
  local masked_default="empty"
  local answer=""

  [[ -n "$default_value" ]] && masked_default="saved"
  read -r -s -p "$label [$masked_default]: " answer
  echo >&2
  if [[ -n "$answer" ]]; then
    printf "%s" "$answer"
  else
    printf "%s" "$default_value"
  fi
}

prompt_menu() {
  local label="$1"
  local default_index="$2"
  shift 2
  local options=("$@")
  local answer=""
  local idx=0
  local entry=""
  local value=""
  local description=""

  while :; do
    echo "$label" >&2
    for idx in "${!options[@]}"; do
      IFS='|' read -r value description <<< "${options[$idx]}"
      printf "  %d) %s\n" "$((idx + 1))" "$description" >&2
    done

    read -r -p "Select an option [$default_index]: " answer
    [[ -z "$answer" ]] && answer="$default_index"

    if [[ "$answer" =~ ^[0-9]+$ ]] && (( answer >= 1 && answer <= ${#options[@]} )); then
      entry="${options[$((answer - 1))]}"
      IFS='|' read -r value description <<< "$entry"
      printf "%s" "$value"
      return 0
    fi

    echo "Enter the number of the desired option." >&2
    echo >&2
  done
}

prompt_admin_connection_detailed() {
  local admin_ok=0

  while (( admin_ok == 0 )); do
    echo
    echo "Administrative connection settings."
    ADMIN_HOST="$(prompt_with_default "Admin host / socket dir" "$ADMIN_HOST")"
    ADMIN_PORT="$(prompt_with_default "Admin port" "$ADMIN_PORT")"
    ADMIN_DATABASE="$(prompt_with_default "Admin database" "$ADMIN_DATABASE")"
    ADMIN_USER="$(prompt_with_default "Admin user" "$ADMIN_USER")"
    ADMIN_PASSWORD="$(prompt_secret_with_default "Admin password" "$ADMIN_PASSWORD")"
    ADMIN_ENV_EXPLICIT=1

    echo "Testing administrative connection..."
    if test_admin_connection; then
      echo "Administrative connection: OK"
      admin_ok=1
    else
      echo "Administrative connection failed."
      echo "Please re-enter admin credentials."
      echo
    fi
  done
}

prompt_auto_admin_connection() {
  echo
  echo "Administrative connection for auto test zone."
  echo "Default admin connection (local socket): ${ADMIN_USER}@${ADMIN_HOST}:${ADMIN_PORT}/${ADMIN_DATABASE}"
  echo "Enter only the postgres password if defaults are OK."
  ADMIN_PASSWORD="$(prompt_secret_with_default "Postgres password" "$ADMIN_PASSWORD")"

  if [[ -n "$ADMIN_PASSWORD" ]]; then
    ADMIN_ENV_EXPLICIT=1
    echo "Testing administrative connection..."
    if test_admin_connection; then
      echo "Administrative connection: OK"
      return 0
    fi
    echo "Default admin connection with the provided password failed."
    echo "Switching to detailed admin settings."
    prompt_admin_connection_detailed
    return 0
  fi

  if can_sudo_postgres; then
    ADMIN_ENV_EXPLICIT=0
    echo "Administrative connection: OK (sudo -u postgres)"
    return 0
  fi

  if test_admin_connection; then
    ADMIN_ENV_EXPLICIT=1
    echo "Administrative connection: OK"
    return 0
  fi

  echo "Default admin connection failed."
  echo "Switching to detailed admin settings."
  prompt_admin_connection_detailed
}

run_interactive_wizard() {
  local preset_choice=""
  local custom_load=0

  if (( PAYLOAD_SIZE_EXPLICIT == 0 )); then
    PAYLOAD_SIZE=32
  fi

  echo "=================================================="
  echo "Interactive wizard: pg-stresser for PostgreSQL"
  echo "=================================================="
  echo "No command-line flags are required."
  echo "Just answer the questions below."
  echo

  MODE="$(prompt_menu "Step 1. Choose the run mode:" 1 \
    "run|Generate SQL requests in the auto-created test zone" \
    "prepare|Create or recreate the auto-created test zone" \
    "delete|Delete test zone")"

  if [[ "$MODE" == "run" ]]; then
    preset_choice="$(prompt_menu "Step 2. Choose the load profile:" 1 \
      "test|Test: short and light run (120 SQL/min, 60 sec)" \
      "base|Base: baseline run (5000 SQL/min, 300 sec)" \
      "custom|Custom: set only RPM and duration")"
    if [[ "$preset_choice" == "custom" ]]; then
      apply_preset base
      PRESET=""
      custom_load=1
    else
      PRESET="$preset_choice"
    fi
  fi

  echo
  if [[ "$MODE" == "run" ]]; then
    echo "SQL generation will run only in the auto-created technical test zone."
    echo "The script will use the dedicated technical database user for SQL generation."
  elif [[ "$MODE" == "delete" ]]; then
    echo "The auto-created technical test zone will be deleted."
  else
    echo "The auto-created technical test zone will be created or recreated."
  fi
  echo

  echo "Technical test zone:"
  echo "  Host:     $PGHOST"
  echo "  Port:     $PGPORT"
  echo "  Database: $PGDATABASE"
  echo "  User:     $PGUSER"
  echo "  Password: $PGPASSWORD"
  echo "  Schema:   $TEST_SCHEMA"
  echo "  Table:    $TEST_TABLE"

  if [[ "$MODE" == "prepare" || "$MODE" == "delete" ]]; then
    prompt_auto_admin_connection
  fi

  if [[ "$MODE" == "run" && $custom_load -eq 1 ]]; then
    echo
    echo "Custom load settings."
    echo "Other workload parameters will use the base profile defaults."
    echo "Payload size stays at ${PAYLOAD_SIZE} unless --payload-size is passed on script start."
    RPM="$(prompt_with_default "RPM (events per minute)" "$RPM")"
    DURATION="$(prompt_with_default "Duration in seconds" "$DURATION")"
  fi

  echo
  echo "Interactive configuration captured."
  echo "Starting the selected workflow..."
  echo
}

apply_preset() {
  case "$1" in
    test)
      RPM=120
      DURATION=60
      INITIAL_ROWS=50
      W_SELECT=70
      W_INSERT=20
      W_UPDATE=8
      W_DELETE=2
      ;;
    base|based)
      RPM=5000
      DURATION=300
      INITIAL_ROWS=1000
      W_SELECT=55
      W_INSERT=25
      W_UPDATE=15
      W_DELETE=5
      ;;
    *)
      die "unsupported preset: $1 (use test or base)"
      ;;
  esac
}

apply_mode() {
  case "$1" in
    prepare)
      SETUP=1
      DELETE_ZONE=0
      RECREATE_ZONE=1
      RUN_LOAD=0
      ;;
    run)
      SETUP=0
      DELETE_ZONE=0
      RECREATE_ZONE=0
      RUN_LOAD=1
      ;;
    delete|cleanup)
      SETUP=0
      DELETE_ZONE=1
      RECREATE_ZONE=0
      RUN_LOAD=0
      ;;
    *)
      die "unsupported mode: $1 (use prepare, run or delete)"
      ;;
  esac
}

ensure_run_tag() {
  if (( RUN_LOAD == 1 )) && [[ -z "$RUN_TAG" ]]; then
    RUN_TAG="pgstresser_$(date +%Y%m%d_%H%M%S)_$RANDOM"
  fi
}

print_launch_summary() {
  echo "=================================================="
  echo "pg-stresser for PostgreSQL"
  echo "=================================================="
  echo "Mode:           ${MODE:-custom}"
  if (( RUN_LOAD == 1 )); then
    [[ -n "$PRESET" ]] && echo "Preset:         $PRESET"
  fi
  echo "Tech account:   ${PGUSER}@${PGHOST}:${PGPORT}/${PGDATABASE}"
  echo "Target objects: ${TARGET_TABLE}"
  if (( SETUP == 1 )); then
    echo "Setup stage:    enabled"
    echo "Recreate zone:  $RECREATE_ZONE"
  else
    echo "Setup stage:    skipped"
  fi
  if (( DELETE_ZONE == 1 )); then
    echo "Delete stage:   enabled"
  else
    echo "Delete stage:   skipped"
  fi
  if (( RUN_LOAD == 1 )); then
    echo "Load stage:     enabled"
    echo "SQL/min / Duration: ${RPM} / ${DURATION}s"
    echo "Session mode:   single persistent psql session"
    echo "Run tag:        $RUN_TAG"
    echo "Initial rows:   $INITIAL_ROWS"
    echo "Payload size:   $PAYLOAD_SIZE"
    if [[ -n "$ONLY" ]]; then
      echo "Operations:     $ONLY"
    else
      echo "Weights:        select=${W_SELECT} insert=${W_INSERT} update=${W_UPDATE} delete=${W_DELETE}"
    fi
  else
    echo "Load stage:     skipped"
  fi
  echo "=================================================="
}

print_examples_hint() {
  echo "Hint:"
  echo "  Wizard:       $0"
  echo "  Tech login:   ${PGUSER}"
  echo "  Tech password:${PGPASSWORD}"
  echo "  Prepare zone: $0 --mode prepare --admin-password <password>"
  echo "  Load test:    $0 --mode run --preset test"
  echo "  Load base:    $0 --mode run --preset base"
  echo "  Delete zone:  $0 --mode delete --admin-password <password>"
}

ARG_COUNT=$#
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --preset) PRESET="${2:-}"; shift 2 ;;
    --interactive) INTERACTIVE=1; shift ;;
    --setup) MODE="prepare"; shift ;;
    --delete-zone) MODE="delete"; shift ;;
    --recreate-zone) RECREATE_ZONE=1; shift ;;
    --host) PGHOST="${2:-}"; shift 2 ;;
    --port) PGPORT="${2:-}"; shift 2 ;;
    --database) PGDATABASE="${2:-}"; shift 2 ;;
    --user) PGUSER="${2:-}"; shift 2 ;;
    --password) PGPASSWORD="${2:-}"; shift 2 ;;
    --schema) TEST_SCHEMA="${2:-}"; shift 2 ;;
    --table) TEST_TABLE="${2:-}"; shift 2 ;;
    --admin-host) ADMIN_HOST="${2:-}"; ADMIN_ENV_EXPLICIT=1; shift 2 ;;
    --admin-port) ADMIN_PORT="${2:-}"; ADMIN_ENV_EXPLICIT=1; shift 2 ;;
    --admin-db) ADMIN_DATABASE="${2:-}"; ADMIN_ENV_EXPLICIT=1; shift 2 ;;
    --admin-user) ADMIN_USER="${2:-}"; ADMIN_ENV_EXPLICIT=1; shift 2 ;;
    --admin-password) ADMIN_PASSWORD="${2:-}"; ADMIN_ENV_EXPLICIT=1; shift 2 ;;
    --rpm) RPM="${2:-}"; shift 2 ;;
    --duration) DURATION="${2:-}"; shift 2 ;;
    --initial-rows) INITIAL_ROWS="${2:-}"; shift 2 ;;
    --payload-size) PAYLOAD_SIZE="${2:-}"; PAYLOAD_SIZE_EXPLICIT=1; shift 2 ;;
    --tag) RUN_TAG="${2:-}"; shift 2 ;;
    --only) ONLY="${2:-}"; shift 2 ;;
    --select-weight) W_SELECT="${2:-}"; shift 2 ;;
    --insert-weight) W_INSERT="${2:-}"; shift 2 ;;
    --update-weight) W_UPDATE="${2:-}"; shift 2 ;;
    --delete-weight) W_DELETE="${2:-}"; shift 2 ;;
    --report-every) REPORT_EVERY="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

export PGHOST PGPORT PGDATABASE PGUSER PGPASSWORD

need psql
need awk
need sort
need date
need wc
need tr
need grep
need head
need tail
need sleep

ONLY="$(printf '%s' "$ONLY" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
MODE="$(printf '%s' "$MODE" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"
PRESET="$(printf '%s' "$PRESET" | tr '[:upper:]' '[:lower:]' | tr -d ' ')"

if (( ARG_COUNT == 0 )) && [[ -t 0 ]] && [[ -t 1 ]]; then
  INTERACTIVE=1
fi

if (( INTERACTIVE == 1 )); then
  run_interactive_wizard
fi

if [[ -n "$PRESET" ]]; then
  apply_preset "$PRESET"
fi

if [[ -n "$MODE" ]]; then
  apply_mode "$MODE"
fi

[[ -n "$MODE" ]] || die "use --mode prepare, --mode run or --mode delete"

ensure_run_tag

if [[ "$MODE" != "prepare" && $RECREATE_ZONE -eq 1 ]]; then
  die "--recreate-zone can be used only with --mode prepare"
fi

[[ "$PGHOST" == /* ]] || die "PostgreSQL connection must use a local socket directory in --host, not TCP/loopback"
[[ "$PGUSER" != "$ADMIN_USER" ]] || die "technical test user must differ from the admin user"
[[ "$PGDATABASE" != "$ADMIN_DATABASE" ]] || die "technical test database must differ from the admin database"

if (( SETUP == 1 || DELETE_ZONE == 1 )) && (( ADMIN_ENV_EXPLICIT == 1 )); then
  [[ "$ADMIN_HOST" == /* ]] || die "Admin connection must use a local socket directory in --admin-host, not TCP/loopback"
fi

if [[ -n "$ONLY" ]]; then
  filtered=""
  IFS=',' read -r -a only_tokens <<< "$ONLY"
  for token in "${only_tokens[@]}"; do
    case "$token" in
      select|insert|update|delete)
        [[ -z "$filtered" ]] && filtered="$token" || filtered="$filtered,$token"
        ;;
      "") ;;
      *)
        die "unsupported value in --only: $token"
        ;;
    esac
  done
  ONLY="$filtered"
fi

is_posint "$RPM" || die "--rpm must be a positive integer"
is_posint "$DURATION" || die "--duration must be a positive integer"
is_nonnegint "$INITIAL_ROWS" || die "--initial-rows must be a non-negative integer"
is_nonnegint "$PAYLOAD_SIZE" || die "--payload-size must be a non-negative integer"
is_nonnegint "$REPORT_EVERY" || die "--report-every must be a non-negative integer"
is_nonnegint "$W_SELECT" || die "--select-weight must be a non-negative integer"
is_nonnegint "$W_INSERT" || die "--insert-weight must be a non-negative integer"
is_nonnegint "$W_UPDATE" || die "--update-weight must be a non-negative integer"
is_nonnegint "$W_DELETE" || die "--delete-weight must be a non-negative integer"
is_posint "$PGPORT" || die "--port must be a positive integer"
is_posint "$ADMIN_PORT" || die "--admin-port must be a positive integer"
[[ -z "$RUN_TAG" || "$RUN_TAG" =~ ^[A-Za-z0-9_.-]+$ ]] || die "--tag may contain only letters, digits, dot, underscore or dash"

require_ident "database" "$PGDATABASE"
require_ident "user" "$PGUSER"
require_ident "schema" "$TEST_SCHEMA"
require_ident "table" "$TEST_TABLE"
require_ident "admin database" "$ADMIN_DATABASE"
require_ident "admin user" "$ADMIN_USER"

op_enabled() {
  local op="$1"
  if [[ -n "$ONLY" ]]; then
    [[ ",$ONLY," == *",$op,"* ]]
    return
  fi

  case "$op" in
    select) (( W_SELECT > 0 )) ;;
    insert) (( W_INSERT > 0 )) ;;
    update) (( W_UPDATE > 0 )) ;;
    delete) (( W_DELETE > 0 )) ;;
    *) return 1 ;;
  esac
}

if [[ -z "$ONLY" ]]; then
  (( W_SELECT + W_INSERT + W_UPDATE + W_DELETE > 0 )) || die "sum of operation weights must be > 0"
fi

if { op_enabled select || op_enabled update; } && (( INITIAL_ROWS == 0 )); then
  die "select/update generation requires --initial-rows > 0"
fi

TARGET_TABLE="${TEST_SCHEMA}.${TEST_TABLE}"
SEED_DELETE_FLOOR="$INITIAL_ROWS"
NEXT_DYNAMIC_ID=$((INITIAL_ROWS + 1))
DELETE_QUEUE=()
PENDING_INSERT_ID=""
PENDING_DELETE_ID=""
SUCC_COUNT=0
ERR_COUNT=0

psql_workload() { psql -v ON_ERROR_STOP=1 "$@"; }
psql_workload_quiet() { psql -v ON_ERROR_STOP=1 -qAt "$@"; }
psql_workload_try() { psql -v ON_ERROR_STOP=1 -qAt -c "$1" >/dev/null 2>&1; }

admin_psql_env() {
  PGOPTIONS="-c client_min_messages=warning" \
  PGHOST="$ADMIN_HOST" \
  PGPORT="$ADMIN_PORT" \
  PGDATABASE="$ADMIN_DATABASE" \
  PGUSER="$ADMIN_USER" \
  PGPASSWORD="$ADMIN_PASSWORD" \
  psql -v ON_ERROR_STOP=1 "$@"
}

admin_try_env() {
  PGOPTIONS="-c client_min_messages=warning" \
  PGHOST="$ADMIN_HOST" \
  PGPORT="$ADMIN_PORT" \
  PGDATABASE="$ADMIN_DATABASE" \
  PGUSER="$ADMIN_USER" \
  PGPASSWORD="$ADMIN_PASSWORD" \
  psql -v ON_ERROR_STOP=1 -qAt -c "$1" >/dev/null 2>&1
}

can_sudo_postgres() {
  command -v sudo >/dev/null 2>&1 || return 1
  sudo -n -u postgres true >/dev/null 2>&1
}

ADMIN_MODE="none"
resolve_admin_mode() {
  if (( ADMIN_ENV_EXPLICIT == 1 )); then
    if admin_try_env "SELECT 1;"; then
      ADMIN_MODE="env"
      return 0
    fi
    die "admin connection failed; verify --admin-* parameters or PGADMIN_* environment"
  fi

  if can_sudo_postgres; then
    ADMIN_MODE="sudo"
    return 0
  fi

  ADMIN_MODE="none"
}

admin_psql() {
  case "$ADMIN_MODE" in
    env) admin_psql_env "$@" ;;
    sudo) sudo -n -u postgres env PGOPTIONS='-c client_min_messages=warning' psql -v ON_ERROR_STOP=1 "$@" ;;
    *) die "admin access is not available for this operation" ;;
  esac
}

admin_exists_role() {
  admin_psql -qAt -d "$ADMIN_DATABASE" -c "SELECT 1 FROM pg_roles WHERE rolname='${PGUSER}';" | grep -q '^1$'
}

admin_exists_db() {
  admin_psql -qAt -d "$ADMIN_DATABASE" -c "SELECT 1 FROM pg_database WHERE datname='${PGDATABASE}';" | grep -q '^1$'
}

require_admin_mode() {
  resolve_admin_mode
  [[ "$ADMIN_MODE" != "none" ]] || die "this action needs admin access; use sudo for local PostgreSQL or pass --admin-*"
  if [[ "$ADMIN_MODE" == "env" && ( $RECREATE_ZONE -eq 1 || $DELETE_ZONE -eq 1 ) ]]; then
    [[ "$ADMIN_DATABASE" != "$PGDATABASE" ]] || die "--admin-db must differ from the technical test database"
    [[ "$ADMIN_USER" != "$PGUSER" ]] || die "--admin-user must differ from the technical test user"
  fi
}

workload_ping() {
  psql -v ON_ERROR_STOP=1 -qAt >/dev/null 2>&1 <<'SQL'
\q
SQL
}

make_payload() {
  local prefix="$1"
  local payload="$prefix"
  local pad_len=0
  local pad=""

  if (( PAYLOAD_SIZE <= 0 )); then
    printf ""
    return 0
  fi

  if (( ${#payload} >= PAYLOAD_SIZE )); then
    printf "%s" "${payload:0:PAYLOAD_SIZE}"
    return 0
  fi

  pad_len=$((PAYLOAD_SIZE - ${#payload}))
  printf -v pad '%*s' "$pad_len" ''
  pad="${pad// /x}"
  printf "%s%s" "$payload" "$pad"
}

tag_sql() {
  local sql="$1"
  local seq="$2"
  local op="$3"
  if [[ -n "$RUN_TAG" ]]; then
    printf "/* pg_stresser_run=%s seq=%s op=%s */ %s" "$RUN_TAG" "$seq" "$op" "$sql"
  else
    printf "%s" "$sql"
  fi
}

ensure_role_and_database() {
  local esc_pass
  esc_pass="$(escape_sql_literal "$PGPASSWORD")"

  if (( RECREATE_ZONE == 1 )); then
    note "recreating role/database: ${PGUSER}/${PGDATABASE}"
    admin_psql -qAt -d "$ADMIN_DATABASE" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${PGDATABASE}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
    admin_psql -q -d "$ADMIN_DATABASE" -c "DROP DATABASE IF EXISTS ${PGDATABASE};" >/dev/null
    admin_psql -q -d "$ADMIN_DATABASE" -c "DROP ROLE IF EXISTS ${PGUSER};" >/dev/null || true
  fi

  if ! admin_exists_role; then
    note "creating role: ${PGUSER}"
    if [[ -n "$PGPASSWORD" ]]; then
      admin_psql -q -d "$ADMIN_DATABASE" -c "CREATE ROLE ${PGUSER} LOGIN PASSWORD '${esc_pass}';" >/dev/null
    else
      admin_psql -q -d "$ADMIN_DATABASE" -c "CREATE ROLE ${PGUSER} LOGIN;" >/dev/null
    fi
  elif [[ -n "$PGPASSWORD" ]]; then
    admin_psql -q -d "$ADMIN_DATABASE" -c "ALTER ROLE ${PGUSER} WITH LOGIN PASSWORD '${esc_pass}';" >/dev/null || true
  fi

  if ! admin_exists_db; then
    note "creating database: ${PGDATABASE}"
    admin_psql -q -d "$ADMIN_DATABASE" -c "CREATE DATABASE ${PGDATABASE} OWNER ${PGUSER};" >/dev/null
  else
    admin_psql -q -d "$ADMIN_DATABASE" -c "ALTER DATABASE ${PGDATABASE} OWNER TO ${PGUSER};" >/dev/null || true
  fi
}

setup_schema_and_table() {
  local table_comment
  table_comment="$(escape_sql_literal "Validation table generated by pg-stresser.sh")"

  PGOPTIONS="-c client_min_messages=warning" psql_workload -q <<SQL
CREATE SCHEMA IF NOT EXISTS ${TEST_SCHEMA} AUTHORIZATION ${PGUSER};
ALTER SCHEMA ${TEST_SCHEMA} OWNER TO ${PGUSER};
DROP TABLE IF EXISTS ${TARGET_TABLE};
CREATE TABLE ${TARGET_TABLE} (
  id BIGSERIAL PRIMARY KEY,
  event_name TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'pg-stresser',
  payload TEXT NOT NULL,
  amount NUMERIC(12,2) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE ${TARGET_TABLE} OWNER TO ${PGUSER};
CREATE INDEX IF NOT EXISTS ${TEST_TABLE}_created_at_idx ON ${TARGET_TABLE}(created_at);
CREATE INDEX IF NOT EXISTS ${TEST_TABLE}_category_idx ON ${TARGET_TABLE}(category);
COMMENT ON TABLE ${TARGET_TABLE} IS '${table_comment}';
SQL

  PGOPTIONS="-c client_min_messages=warning" psql_workload -q <<SQL
INSERT INTO ${TARGET_TABLE}(event_name, category, payload, amount)
SELECT
  'seed_' || g,
  'seed',
  repeat('S', ${PAYLOAD_SIZE}),
  (random()*9999.99+0.01)::numeric(12,2)
FROM generate_series(1, ${INITIAL_ROWS}) AS g;
SQL
}

delete_test_zone() {
  echo "[Stage 1/1] Deleting test zone"
  require_admin_mode
  note "dropping database if exists: ${PGDATABASE}"
  admin_psql -qAt -d "$ADMIN_DATABASE" -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${PGDATABASE}' AND pid <> pg_backend_pid();" >/dev/null 2>&1 || true
  admin_psql -q -d "$ADMIN_DATABASE" -c "DROP DATABASE IF EXISTS ${PGDATABASE};" >/dev/null
  note "dropping role if exists: ${PGUSER}"
  admin_psql -q -d "$ADMIN_DATABASE" -c "DROP ROLE IF EXISTS ${PGUSER};" >/dev/null || true
  note "test zone deleted: ${PGDATABASE}/${PGUSER}"
}

prepare_environment() {
  if (( SETUP == 1 )); then
    echo "[Stage 1/1] Preparing test zone"
    require_admin_mode
    ensure_role_and_database
    workload_ping || die "cannot connect with workload connection after auto-setup"

    setup_schema_and_table
    note "test zone ready: ${PGDATABASE}.${TARGET_TABLE} as ${PGUSER}"
    note "SQL generation must be started with the technical account: ${PGUSER}"
    note "technical account password: ${PGPASSWORD}"
    note "next run command: $0 --mode run --preset test"
    return 0
  fi

  echo "[Stage 1/1] Using the auto-created test zone"
  echo "No pre-run SQL checks will be executed."
}

choose_op() {
  local allowed="$1"
  local ops=()
  local total=0
  local op=""
  local w=0
  local r=0
  local acc=0

  if [[ -n "$allowed" ]]; then
    IFS=',' read -r -a ops <<< "$allowed"
  else
    ops=(select insert update delete)
  fi

  for op in "${ops[@]}"; do
    case "$op" in
      select) w=$W_SELECT ;;
      insert) w=$W_INSERT ;;
      update) w=$W_UPDATE ;;
      delete) w=$W_DELETE ;;
      *) w=0 ;;
    esac
    (( w > 0 )) || continue
    total=$((total + w))
  done

  (( total > 0 )) || die "no operations are enabled"

  r=$(( (RANDOM % total) + 1 ))
  acc=0
  for op in "${ops[@]}"; do
    case "$op" in
      select) w=$W_SELECT ;;
      insert) w=$W_INSERT ;;
      update) w=$W_UPDATE ;;
      delete) w=$W_DELETE ;;
      *) w=0 ;;
    esac
    (( w > 0 )) || continue
    acc=$((acc + w))
    if (( r <= acc )); then
      printf "%s" "$op"
      return 0
    fi
  done

  printf "insert"
}

rand_1_n() {
  local n="$1"
  echo $(( (RANDOM % n) + 1 ))
}

ERR_COOLDOWN=2
_last_err=0
err_throttled() {
  local msg="$1"
  local ts
  ts="$(date +%s)"
  if (( ts - _last_err >= ERR_COOLDOWN )); then
    _last_err="$ts"
    echo "[ERROR] $msg" >&2
  fi
}

make_sql_for_op() {
  local op="$1"
  local sql=""
  local id=""
  local payload=""
  local payload_sql=""

  PENDING_INSERT_ID=""
  PENDING_DELETE_ID=""

  case "$op" in
    select)
      id="$(rand_1_n "$INITIAL_ROWS")"
      sql="SELECT id, event_name, category, amount, created_at FROM ${TARGET_TABLE} WHERE id = ${id};"
      ;;
    insert)
      PENDING_INSERT_ID="$NEXT_DYNAMIC_ID"
      payload="$(make_payload "ins_${RANDOM}${RANDOM}_")"
      payload_sql="$(escape_sql_literal "$payload")"
      sql="INSERT INTO ${TARGET_TABLE}(event_name, category, payload, amount) VALUES ('evt_${RANDOM}${RANDOM}', 'insert', '${payload_sql}', (random()*9999.99+0.01)::numeric(12,2));"
      ;;
    update)
      id="$(rand_1_n "$INITIAL_ROWS")"
      payload="$(make_payload "upd_${RANDOM}${RANDOM}_")"
      payload_sql="$(escape_sql_literal "$payload")"
      sql="UPDATE ${TARGET_TABLE} SET amount = (random()*9999.99+0.01)::numeric(12,2), payload = '${payload_sql}', updated_at = now() WHERE id = ${id};"
      ;;
    delete)
      if (( ${#DELETE_QUEUE[@]} > 0 )); then
        PENDING_DELETE_ID="${DELETE_QUEUE[0]}"
      else
        PENDING_DELETE_ID="$NEXT_DYNAMIC_ID"
      fi
      sql="DELETE FROM ${TARGET_TABLE} WHERE id = ${PENDING_DELETE_ID};"
      ;;
    *)
      return 1
      ;;
  esac

  printf "%s" "$sql"
}

WORKLOAD_IN_FD=""
WORKLOAD_OUT_FD=""
WORKLOAD_PID=""
WORKLOAD_SESSION_SEQ=0
SQL_SEQ=0

start_workload_session() {
  coproc PSQL_SESSION {
    PGOPTIONS="-c client_min_messages=warning" \
    psql -X -v ON_ERROR_STOP=0 -v VERBOSITY=terse -qAt 2>&1
  }

  WORKLOAD_IN_FD="${PSQL_SESSION[1]}"
  WORKLOAD_OUT_FD="${PSQL_SESSION[0]}"
  WORKLOAD_PID="${PSQL_SESSION_PID:-}"

  printf '\\echo __PSQL_READY__\n' >&"$WORKLOAD_IN_FD" || return 1

  local line=""
  while IFS= read -r -u "$WORKLOAD_OUT_FD" line; do
    [[ "$line" == "__PSQL_READY__" ]] && return 0
  done

  return 1
}

stop_workload_session() {
  [[ -n "$WORKLOAD_IN_FD" ]] || return 0

  printf '\\q\n' >&"$WORKLOAD_IN_FD" 2>/dev/null || true
  exec {WORKLOAD_IN_FD}>&- 2>/dev/null || true
  exec {WORKLOAD_OUT_FD}<&- 2>/dev/null || true
  wait "$WORKLOAD_PID" >/dev/null 2>&1 || true

  WORKLOAD_IN_FD=""
  WORKLOAD_OUT_FD=""
  WORKLOAD_PID=""
}

run_sql_in_session() {
  local sql="$1"
  local marker=""
  local line=""
  local had_error=0

  WORKLOAD_SESSION_SEQ=$((WORKLOAD_SESSION_SEQ + 1))
  marker="__PG_DONE_${WORKLOAD_SESSION_SEQ}__"

  printf '\\o /dev/null\n' >&"$WORKLOAD_IN_FD" || return 1
  printf '%s\n' "$sql" >&"$WORKLOAD_IN_FD" || return 1
  printf '\\o\n' >&"$WORKLOAD_IN_FD" || return 1
  printf '\\echo %s\n' "$marker" >&"$WORKLOAD_IN_FD" || return 1

  while IFS= read -r -u "$WORKLOAD_OUT_FD" line; do
    [[ "$line" == ERROR:* || "$line" == FATAL:* || "$line" == PANIC:* ]] && had_error=1
    [[ "$line" == "$marker" ]] && (( had_error == 0 )) && return 0
    [[ "$line" == "$marker" ]] && return 1
  done

  return 1
}

do_operation() {
  local op="$1"
  local base_sql=""
  local sql=""

  base_sql="$(make_sql_for_op "$op")" || {
    ERR_COUNT=$((ERR_COUNT + 1))
    return 1
  }
  SQL_SEQ=$((SQL_SEQ + 1))
  sql="$(tag_sql "$base_sql" "$SQL_SEQ" "$op")"

  if ! run_sql_in_session "$sql"; then
    ERR_COUNT=$((ERR_COUNT + 1))
    err_throttled "DB op failed (${op})"
    return 1
  fi

  case "$op" in
    insert)
      if [[ -n "$PENDING_INSERT_ID" ]]; then
        DELETE_QUEUE+=("$PENDING_INSERT_ID")
        NEXT_DYNAMIC_ID=$((PENDING_INSERT_ID + 1))
      fi
      ;;
    delete)
      if [[ -n "$PENDING_DELETE_ID" ]] && (( ${#DELETE_QUEUE[@]} > 0 )) && [[ "${DELETE_QUEUE[0]}" == "$PENDING_DELETE_ID" ]]; then
        DELETE_QUEUE=("${DELETE_QUEUE[@]:1}")
      fi
      ;;
  esac

  SUCC_COUNT=$((SUCC_COUNT + 1))
  return 0
}

SCRIPT_START_DT="$(now_dt)"
SCRIPT_START_NS="$(date +%s%N)"
echo "Script start: $SCRIPT_START_DT"
print_launch_summary

if (( DELETE_ZONE == 1 )); then
  delete_test_zone
  echo
  echo "Test zone deletion finished successfully."
  exit 0
fi

prepare_environment

if (( RUN_LOAD == 0 )); then
  echo
  echo "Preparation finished successfully."
  print_examples_hint
  exit 0
fi

TOTAL_SUBMISSIONS=$(( (RPM * DURATION) / 60 ))
rem=$(( (RPM * DURATION) % 60 ))
if (( rem >= 30 )); then
  TOTAL_SUBMISSIONS=$((TOTAL_SUBMISSIONS + 1))
fi
(( TOTAL_SUBMISSIONS > 0 )) || die "computed submissions=0"

TARGET_RPS="$(awk -v rpm="$RPM" 'BEGIN{printf "%.6f", rpm/60.0}')"
INTERVAL_NS="$(awk -v s="$TOTAL_SUBMISSIONS" -v d="$DURATION" 'BEGIN{
  printf "%.0f", (d/s)*1000000000.0
}')"

echo "Opening workload session..."
start_workload_session || die "cannot start persistent workload session; check --host --port --database --user --password"
trap 'stop_workload_session' EXIT
if (( SESSION_WARMUP_SECONDS > 0 )); then
  echo "Workload session is ready."
  echo "Waiting ${SESSION_WARMUP_SECONDS} sec before timed load start..."
  sleep "$SESSION_WARMUP_SECONDS"
fi

LOAD_START_DT="$(now_dt)"
echo "Load start:  $LOAD_START_DT"
echo
echo "Load plan"
rule
echo "Target rate:           $RPM SQL/min (~$TARGET_RPS ops/sec)"
echo "Duration:              $DURATION sec"
echo "Planned submissions:   $TOTAL_SUBMISSIONS"
echo "Session mode:          single persistent psql session"
echo "Run tag:               $RUN_TAG"
echo "Seed rows:             $INITIAL_ROWS"
echo "Payload size:          $PAYLOAD_SIZE"
if [[ -n "$ONLY" ]]; then
  echo "Operations:            $ONLY"
else
  echo "Operation mix:         select=${W_SELECT} insert=${W_INSERT} update=${W_UPDATE} delete=${W_DELETE}"
fi
echo "Interval:              ${INTERVAL_NS} ns"
echo

START_NS="$(date +%s%N)"
NEXT_FIRE_NS="$START_NS"
SUBMITTED=0
LAST_REPORT_S=0

while (( SUBMITTED < TOTAL_SUBMISSIONS )); do
  while :; do
    NOW_NS="$(date +%s%N)"
    if (( NOW_NS >= NEXT_FIRE_NS )); then
      break
    fi
    diff=$((NEXT_FIRE_NS - NOW_NS))
    if (( diff > 2000000 )); then
      sleep 0.001
    else
      :
    fi
  done

  op="$(choose_op "$ONLY")"
  do_operation "$op" || true

  SUBMITTED=$((SUBMITTED + 1))
  NEXT_FIRE_NS=$((NEXT_FIRE_NS + INTERVAL_NS))

  if (( REPORT_EVERY > 0 )); then
    now_s="$(date +%s)"
    elapsed_s=$(( now_s - (START_NS / 1000000000) ))
    if (( elapsed_s - LAST_REPORT_S >= REPORT_EVERY )); then
      LAST_REPORT_S="$elapsed_s"
      echo "[Progress] ${elapsed_s}s | submitted ${SUBMITTED}/${TOTAL_SUBMISSIONS} | success ${SUCC_COUNT} | errors ${ERR_COUNT}"
    fi
  fi
done

stop_workload_session
trap - EXIT

TOTAL_END_NS="$(date +%s%N)"
TOTAL_TIME_SEC="$(awk -v a="$START_NS" -v b="$TOTAL_END_NS" 'BEGIN{printf "%.6f",(b-a)/1e9}')"
LOAD_END_DT="$(now_dt)"
echo "Load end:    $LOAD_END_DT"

SUCC="$SUCC_COUNT"
ERRS="$ERR_COUNT"
COMPLETED=$((SUCC + ERRS))
LOST=$((SUBMITTED - COMPLETED))
(( LOST < 0 )) && LOST=0
LOSS_PCT="$(awk -v l="$LOST" -v s="$SUBMITTED" 'BEGIN{ if(s>0) printf "%.2f",(l/s)*100; else print "0.00"}')"
ACTUAL_RPM="$(awk -v s="$SUCC" -v d="$DURATION" 'BEGIN{ if(d>0) printf "%.1f",(s/d)*60; else print "0.0"}')"

SCRIPT_END_DT="$(now_dt)"
SCRIPT_END_NS="$(date +%s%N)"
SCRIPT_ELAPSED="$(awk -v a="$SCRIPT_START_NS" -v b="$SCRIPT_END_NS" 'BEGIN{printf "%.2f",(b-a)/1e9}')"

echo
echo "=================================================="
echo "RESULTS - ${RPM} SQL/min schedule"
echo "=================================================="
echo "Run window"
rule
echo "Script start:   $SCRIPT_START_DT"
echo "Script end:     $SCRIPT_END_DT"
echo "Script elapsed: ${SCRIPT_ELAPSED} sec"
echo
echo "Load start:     $LOAD_START_DT"
echo "Load end:       $LOAD_END_DT"
echo "Wall time:      ${TOTAL_TIME_SEC} sec"
echo "Window (target): ${DURATION} sec"
echo
echo "Execution summary"
rule
echo "Target table:   ${TARGET_TABLE}"
echo "Run tag:        ${RUN_TAG}"
echo "Submitted:      $SUBMITTED (planned exact)"
echo "Completed:      $COMPLETED"
echo "Lost (gen):     $LOST (${LOSS_PCT}%)"
echo
echo "Successful:     $SUCC"
echo "Errors:         $ERRS"
echo "Actual SQL/min (by target window): $ACTUAL_RPM"
echo "=================================================="
